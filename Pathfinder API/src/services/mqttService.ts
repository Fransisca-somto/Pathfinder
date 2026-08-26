import mqtt from 'mqtt';
import { supabase } from '../config/supabase';
import { emitLiveTelemetry, emitNewAlert } from '../sockets/socketManager';
import { startTrip, endTrip } from './tripService';
import { processVehicleLocation } from './zoneService';

const MQTT_BROKER_URL = process.env.MQTT_BROKER_URL || 'mqtt://broker.hivemq.com:1883';
const TELEMETRY_TOPIC = 'pathfinder/telemetry';
const ALERTS_TOPIC = 'pathfinder/alerts';

export let mqttClient: mqtt.MqttClient;

// Cache device-to-owner mappings so we don't hit the DB on every MQTT message
const deviceOwnerCache: Map<string, string> = new Map();

// Track previous status to detect trip start/end
const deviceStatusCache: Map<string, string> = new Map();

// Keep track of timeouts for each device to mark them offline after 2 minutes of silence
const deviceTimeouts: Map<string, NodeJS.Timeout> = new Map();

// Keep track of overspeeding alerts to prevent spam (1 minute cooldown)
const lastOverspeedAlerts: Map<string, number> = new Map();
const OVERSPEED_THRESHOLD_KMPH = 80;
const OVERSPEED_COOLDOWN_MS = 60000;

export const initializeMqtt = () => {
  console.log(`[MQTT] Connecting to broker: ${MQTT_BROKER_URL}`);
  
  mqttClient = mqtt.connect(MQTT_BROKER_URL);

  mqttClient.on('connect', () => {
    console.log('[MQTT] Connected to broker successfully!');

    // Subscribe to the topics the ESP32 publishes to
    mqttClient.subscribe([TELEMETRY_TOPIC, ALERTS_TOPIC], (err) => {
      if (err) {
        console.error('[MQTT] Subscribe error:', err);
      } else {
        console.log(`[MQTT] Subscribed to: ${TELEMETRY_TOPIC}, ${ALERTS_TOPIC}`);
      }
    });
  });

  mqttClient.on('message', (topic: string, message: Buffer) => {
    try {
      const payload = JSON.parse(message.toString());
      console.log(`[MQTT] ${topic} =>`, payload);

      if (topic === TELEMETRY_TOPIC) {
        handleTelemetry(payload);
      } else if (topic === ALERTS_TOPIC) {
        triggerAlert(payload);
      }
    } catch (err) {
      console.error('[MQTT] Failed to parse message:', message.toString());
    }
  });

  mqttClient.on('error', (err) => {
    console.error('[MQTT] Connection error:', err);
  });

  mqttClient.on('offline', () => {
    console.warn('[MQTT] Client went offline');
  });

  mqttClient.on('reconnect', () => {
    console.log('[MQTT] Reconnecting...');
  });
};

export const publishCommand = (deviceId: string, command: string, payload: any = {}) => {
  if (!mqttClient || !mqttClient.connected) {
    console.warn('[MQTT] Cannot publish command, mqttClient not connected');
    return;
  }
  
  const topic = 'pathfinder/commands';
  const message = JSON.stringify({
    deviceId,
    command,
    ...payload
  });
  
  mqttClient.publish(topic, message);
  console.log(`[MQTT] Published command to ${deviceId}:`, command);
};

// Look up the owner of a device (with caching)
const getDeviceOwner = async (deviceId: string): Promise<string | null> => {
  // Check cache first
  if (deviceOwnerCache.has(deviceId)) {
    return deviceOwnerCache.get(deviceId)!;
  }

  // Query Supabase
  const { data, error } = await supabase
    .from('vehicles')
    .select('owner_id')
    .ilike('device_id', deviceId)
    .single();

  if (error || !data) {
    return null;
  }

  // Cache the result
  deviceOwnerCache.set(deviceId, data.owner_id);
  return data.owner_id;
};

// Reset the 120-second offline timeout for a device
const resetDeviceTimeout = (deviceId: string, ownerId: string) => {
  if (deviceTimeouts.has(deviceId)) {
    clearTimeout(deviceTimeouts.get(deviceId)!);
  }

  const timeout = setTimeout(async () => {
    console.log(`[MQTT] Device ${deviceId} timed out after 120 seconds of silence. Marking offline.`);
    deviceTimeouts.delete(deviceId);

    // Update DB
    await supabase
      .from('vehicles')
      .update({ status: 'offline' })
      .ilike('device_id', deviceId);

    // Notify Flutter App
    emitLiveTelemetry({
      deviceId: deviceId,
      status: 'offline',
      timestamp: new Date().toISOString(),
    }, ownerId);
  }, 120000); // 2 minutes

  deviceTimeouts.set(deviceId, timeout);
};

// Clear cache for a specific device (call this when a vehicle is registered or deleted)
export const clearDeviceCache = (deviceId: string) => {
  deviceOwnerCache.delete(deviceId);
};

// Handle incoming GPS telemetry from ESP32
const handleTelemetry = async (data: any) => {
  const deviceId = data.deviceId?.toUpperCase();
  if (!deviceId) {
    return;
  }

  // Look up who owns this device
  const ownerId = await getDeviceOwner(deviceId);
  
  // Get vehicle_id for trips
  let vehicleId = '';
  if (ownerId) {
    const { data } = await supabase.from('vehicles').select('id').ilike('device_id', deviceId).single();
    if (data) vehicleId = data.id;
  }

  if (!ownerId) {
    console.warn(`[MQTT] Unclaimed device: ${deviceId} — ignoring telemetry`);
    return;
  }

  const updatePayload: any = {};
  if (data.lat !== undefined && data.lng !== undefined) {
    updatePayload.current_latitude = data.lat;
    updatePayload.current_longitude = data.lng;
    updatePayload.last_known_location = `${data.lat}, ${data.lng}`;
  }
  if (data.speed !== undefined) {
    updatePayload.current_speed = data.speed;
  }
  if (data.temperature !== undefined) {
    updatePayload.engine_temperature = data.temperature;
  }
  
  // Determine status
  let finalStatus = 'parked';
  if (data.status) {
    // If 'online' is sent without speed, it implies parked, but we can pass 'online' to DB or let it be.
    // The DB enum is 'moving', 'parked', 'offline', 'alarm'. So 'online' is best mapped to 'parked' or ignored if lat/lng is missing.
    // Let's just use what they passed, unless it's 'online' which we map to 'parked'.
    finalStatus = data.status === 'online' ? 'parked' : data.status;
  } else if (data.speed !== undefined) {
    finalStatus = data.speed > 0 ? 'moving' : 'parked';
  }
  updatePayload.status = finalStatus;

  // Update the vehicle's location in the database
  await supabase
    .from('vehicles')
    .update(updatePayload)
    .ilike('device_id', deviceId);

  // --- TRIP TRACKING LOGIC ---
  if (vehicleId && data.lat && data.lng) {
    const prevStatus = deviceStatusCache.get(deviceId) || 'parked';
    
    if (prevStatus !== 'moving' && finalStatus === 'moving') {
      await startTrip(vehicleId, data.lat, data.lng);
    } else if (prevStatus === 'moving' && (finalStatus === 'parked' || finalStatus === 'offline')) {
      await endTrip(vehicleId, data.lat, data.lng);
    }
    
    deviceStatusCache.set(deviceId, finalStatus);

    // Evaluate against assigned zones
    await processVehicleLocation(vehicleId, deviceId, data.lat, data.lng, ownerId);
  }
  // ---------------------------

  // Build the telemetry payload
  const telemetryPayload = {
    deviceId: deviceId,
    lat: data.lat,
    lng: data.lng,
    speed: data.speed,
    temperature: data.temperature,
    status: finalStatus,
    timestamp: new Date().toISOString(),
  };

  // Forward ONLY to the owner's private WebSocket room
  console.log(`[MQTT] Forwarding telemetry for device ${deviceId} to owner ${ownerId}. Status: ${finalStatus}`);
  emitLiveTelemetry(telemetryPayload, ownerId);

  if (finalStatus === 'offline') {
    if (deviceTimeouts.has(deviceId)) {
      clearTimeout(deviceTimeouts.get(deviceId)!);
      deviceTimeouts.delete(deviceId);
    }
  } else {
    resetDeviceTimeout(deviceId, ownerId);
  }

  // Check for overspeeding
  if (data.speed && data.speed > OVERSPEED_THRESHOLD_KMPH) {
    const now = Date.now();
    const lastAlertTime = lastOverspeedAlerts.get(deviceId) || 0;
    if (now - lastAlertTime > OVERSPEED_COOLDOWN_MS) {
      lastOverspeedAlerts.set(deviceId, now);
      
      // Trigger an alert internally
      triggerAlert({
        deviceId: deviceId,
        type: 'speed',
        message: `Overspeeding detected: ${Math.round(data.speed)} km/h`,
      });
    }
  }
};

// Handle incoming alerts from ESP32 (e.g. panic button)
export const triggerAlert = async (data: any) => {
  const deviceId = data.deviceId;
  if (!deviceId) return;

  const ownerId = await getDeviceOwner(deviceId);
  if (!ownerId) {
    console.warn(`[MQTT] Alert from unclaimed device: ${deviceId} — ignoring`);
    return;
  }

  console.log(`[MQTT] Alert from device ${deviceId} for owner ${ownerId}:`, data);

  // Save alert to database
  const { data: vehicle } = await supabase
    .from('vehicles')
    .select('id')
    .ilike('device_id', deviceId)
    .single();

  let insertedAlertId = '';

  if (vehicle) {
    const { data: newAlert } = await supabase.from('alerts').insert({
      type: data.type || 'system',
      vehicle_id: vehicle.id,
      message: data.message || 'Alert from device',
      owner_id: ownerId,
    }).select('id').single();
    
    if (newAlert) {
      insertedAlertId = newAlert.id;
    }

    // Special Handling: If this is an enrollment success alert, update the profile status!
    if (data.type === 'system') {
      if (data.message === 'Fingerprint enrollment successful') {
        console.log(`[MQTT] Detected enrollment success for vehicle ${vehicle.id}. Updating DB...`);
        await supabase
          .from('fingerprint_profiles')
          .update({ status: 'enrolled' })
          .eq('vehicle_id', vehicle.id)
          .eq('status', 'pending');
      } else if (data.message === 'Fingerprint enrollment timeout') {
        console.log(`[MQTT] Detected enrollment timeout for vehicle ${vehicle.id}. Cleaning up DB...`);
        await supabase
          .from('fingerprint_profiles')
          .delete()
          .eq('vehicle_id', vehicle.id)
          .eq('status', 'pending');
      }
    } else if (data.type === 'authSuccess') {
      console.log(`[MQTT] Authentication success for vehicle ${vehicle.id}. Unlocking engine in DB...`);
      await supabase
        .from('vehicles')
        .update({ is_engine_locked: false })
        .eq('id', vehicle.id);
    } else if (data.type === 'authFailure') {
      console.log(`[MQTT] Authentication failure for vehicle ${vehicle.id}. Ensure engine remains locked in DB...`);
      await supabase
        .from('vehicles')
        .update({ is_engine_locked: true })
        .eq('id', vehicle.id);
    }
  }

  // Forward ONLY to the owner
  emitNewAlert({
    id: insertedAlertId,
    deviceId: deviceId,
    type: data.type || 'system',
    message: data.message || 'Alert from device',
    timestamp: new Date().toISOString(),
  }, ownerId);
};

