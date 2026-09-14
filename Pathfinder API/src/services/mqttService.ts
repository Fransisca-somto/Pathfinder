import mqtt from 'mqtt';
import { supabase } from '../config/supabase';
import { emitLiveTelemetry, emitNewAlert } from '../sockets/socketManager';
import { startTrip, endTrip, appendTripCoordinate } from './tripService';
import { processVehicleLocation } from './zoneService';

const MQTT_BROKER_URL = process.env.MQTT_BROKER_URL || 'mqtt://broker.hivemq.com:1883';
const TELEMETRY_TOPIC = 'pathfinder/telemetry';
const ALERTS_TOPIC = 'pathfinder/alerts';
const STATUS_TOPIC = 'pathfinder/status';

export let mqttClient: mqtt.MqttClient;

// Cache device-to-owner mappings so we don't hit the DB on every MQTT message
const deviceOwnerCache: Map<string, string> = new Map();

// Track previous status to detect trip start/end
const deviceStatusCache: Map<string, string> = new Map();

// Keep track of timeouts for each device to mark them offline after 2 minutes of silence
const deviceTimeouts: Map<string, NodeJS.Timeout> = new Map();

// Track last telemetry time to override stale LWT messages
const lastTelemetryTimes: Map<string, number> = new Map();

// Track when a device started moving to prevent jitter-based phantom trips
const deviceMovingSince: Map<string, number> = new Map();



// Keep track of overspeeding alerts to prevent spam (1 minute cooldown)
const lastOverspeedAlerts: Map<string, number> = new Map();
const OVERSPEED_THRESHOLD_KMPH = 80;
const OVERSPEED_COOLDOWN_MS = 60000;

// Deduplication cache for SD-card-queued and re-sent alerts.
// Key: "deviceId|type|message|uptime" — Value: timestamp when cached.
// Entries auto-expire after 60 seconds via setTimeout.
const alertDedupeCache: Map<string, number> = new Map();
const ALERT_DEDUPE_TTL_MS = 60000;

export const initializeMqtt = () => {
  console.log(`[MQTT] Connecting to broker: ${MQTT_BROKER_URL}`);
  
  mqttClient = mqtt.connect(MQTT_BROKER_URL);

  mqttClient.on('connect', () => {
    console.log('[MQTT] Connected to broker successfully!');

    // Subscribe to the topics the ESP32 publishes to
    mqttClient.subscribe([TELEMETRY_TOPIC, ALERTS_TOPIC, STATUS_TOPIC], (err) => {
      if (err) {
        console.error('[MQTT] Subscribe error:', err);
      } else {
        console.log(`[MQTT] Subscribed to: ${TELEMETRY_TOPIC}, ${ALERTS_TOPIC}, ${STATUS_TOPIC}`);
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
      } else if (topic === STATUS_TOPIC) {
        handleStatus(payload);
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
    deviceId: deviceId.toLowerCase(),
    command,
    payload
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

// Mark a device offline explicitly
const markDeviceOffline = async (deviceId: string, ownerId: string) => {
  console.log(`[MQTT] Device ${deviceId} is now offline.`);
  if (deviceTimeouts.has(deviceId)) {
    clearTimeout(deviceTimeouts.get(deviceId)!);
    deviceTimeouts.delete(deviceId);
  }

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
};

// Reset the 120-second offline timeout for a device
const resetDeviceTimeout = (deviceId: string, ownerId: string) => {
  if (deviceTimeouts.has(deviceId)) {
    clearTimeout(deviceTimeouts.get(deviceId)!);
  }

  const timeout = setTimeout(() => {
    console.log(`[MQTT] Device ${deviceId} timed out after 120 seconds of silence.`);
    markDeviceOffline(deviceId, ownerId);
  }, 120000); // 2 minutes

  deviceTimeouts.set(deviceId, timeout);
};

// Clear cache for a specific device (call this when a vehicle is registered or deleted)
export const clearDeviceCache = (deviceId: string) => {
  deviceOwnerCache.delete(deviceId);
};

// Handle explicit LWT / status messages
const handleStatus = async (data: any) => {
  const deviceId = data.deviceId?.toUpperCase();
  if (!deviceId) return;

  const ownerId = await getDeviceOwner(deviceId);
  if (!ownerId) return;

  if (data.status === 'offline') {
    const lastTime = lastTelemetryTimes.get(deviceId) || 0;
    if (Date.now() - lastTime < 30000) {
      console.log(`[MQTT] Ignoring stale offline status for ${deviceId}, telemetry received recently`);
      return;
    }
    await markDeviceOffline(deviceId, ownerId);
  } else if (data.status === 'online') {
    console.log(`[MQTT] Device ${deviceId} reported online. Waiting for telemetry...`);
    if (deviceTimeouts.has(deviceId)) {
      clearTimeout(deviceTimeouts.get(deviceId)!);
      deviceTimeouts.delete(deviceId);
    }
  }
};

// Handle incoming GPS telemetry from ESP32
const handleTelemetry = async (data: any) => {
  const deviceId = data.deviceId?.toUpperCase();
  if (!deviceId) {
    return;
  }

  lastTelemetryTimes.set(deviceId, Date.now());

  // --- TELEMETRY VALIDATION ---
  if (data.satellites !== undefined && data.satellites > 32) {
    console.warn(`[MQTT] Rejecting telemetry for ${deviceId}: Impossible satellite count (${data.satellites})`);
    return;
  }
  if (data.lat !== undefined && data.lng !== undefined) {
    if (Math.abs(data.lat) < 1.0 && Math.abs(data.lng) < 1.0) {
      console.warn(`[MQTT] Rejecting telemetry for ${deviceId}: Coordinates near Null Island (${data.lat}, ${data.lng})`);
      return;
    }
  }
  // ----------------------------


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
  if (data.temperature !== undefined && data.temperature !== null) {
    updatePayload.engine_temperature = data.temperature;
  }
  if (data.battery_voltage !== undefined) {
    updatePayload.battery_voltage = data.battery_voltage;
  }
  if (data.charging !== undefined) {
    updatePayload.charging = data.charging;
  }
  if (data.power_cut !== undefined) {
    updatePayload.power_cut = data.power_cut;
  }
  if (data.driverId !== undefined) {
    updatePayload.current_driver_id = data.driverId;
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
      const movingSince = deviceMovingSince.get(deviceId) || Date.now();
      deviceMovingSince.set(deviceId, movingSince);
      
      if (Date.now() - movingSince >= 10000) { // 10s hysteresis
        await startTrip(vehicleId, data.lat, data.lng);
        deviceMovingSince.delete(deviceId);
        deviceStatusCache.set(deviceId, 'moving');
      } else {
        // Keep as parked internally until hysteresis passes
        deviceStatusCache.set(deviceId, prevStatus);
      }
    } else if (prevStatus === 'moving' && (finalStatus === 'parked' || finalStatus === 'offline')) {
      await endTrip(vehicleId, data.lat, data.lng);
      deviceMovingSince.delete(deviceId);
      deviceStatusCache.set(deviceId, finalStatus);
    } else if (prevStatus === 'moving' && finalStatus === 'moving') {
      appendTripCoordinate(vehicleId, data.lat, data.lng);
      deviceStatusCache.set(deviceId, finalStatus);
    } else {
      deviceMovingSince.delete(deviceId);
      deviceStatusCache.set(deviceId, finalStatus);
    }

    // Evaluate against assigned zones
    await processVehicleLocation(vehicleId, deviceId, data.lat, data.lng, data.acc, ownerId);
  }
  // ---------------------------

  // Build the telemetry payload
  const telemetryPayload = {
    deviceId: deviceId,
    lat: data.lat,
    lng: data.lng,
    speed: data.speed,
    acc: data.acc,
    battery: data.battery,
    battery_voltage: data.battery_voltage,
    charging: data.charging ?? false,
    power_cut: data.power_cut ?? false,
    driverId: data.driverId ?? -1,
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

  // --- DEDUPLICATION ---
  // The firmware queues alerts on SD card and drains them 3-at-a-time
  // after reconnection. A failed queue rewrite causes deliberate re-sends.
  // We deduplicate on (deviceId, type, message, uptime) with a 60s TTL.
  const dedupeKey = `${deviceId}|${data.type || 'system'}|${data.message || ''}|${data.uptime ?? ''}`;
  if (alertDedupeCache.has(dedupeKey)) {
    console.log(`[MQTT] Duplicate alert suppressed (key: ${dedupeKey})`);
    return;
  }
  alertDedupeCache.set(dedupeKey, Date.now());
  setTimeout(() => alertDedupeCache.delete(dedupeKey), ALERT_DEDUPE_TTL_MS);
  // ---------------------

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
      uptime: data.uptime ?? null,
      driver_id: data.driverId ?? null,
    }).select('id').single();
    
    if (newAlert) {
      insertedAlertId = newAlert.id;
    }

    // Enrollment progress — no DB action needed, just forwarded to the app via WebSocket
    if (data.type === 'enrollProgress') {
      // Already saved to DB and forwarded below — nothing extra to do
    }
    // Enrollment success — mark the pending profile as fully enrolled
    else if (data.type === 'enrollSuccess') {
      console.log(`[MQTT] Enrollment success for vehicle ${vehicle.id}. Marking profile enrolled...`);
      await supabase
        .from('fingerprint_profiles')
        .update({ status: 'enrolled', enrolled_at: new Date().toISOString() })
        .eq('vehicle_id', vehicle.id)
        .eq('status', 'pending');
    }
    // Enrollment failed / timed out — delete the orphaned pending profile
    else if (data.type === 'enrollFailed') {
      console.log(`[MQTT] Enrollment failed for vehicle ${vehicle.id}. Cleaning up pending profile...`);
      await supabase
        .from('fingerprint_profiles')
        .delete()
        .eq('vehicle_id', vehicle.id)
        .eq('status', 'pending');
    }
    else if (data.type === 'authSuccess') {
      const isReAuth = data.message?.includes('re-authenticated');
      if (isReAuth) {
        console.log(`[MQTT] Driver re-authenticated for vehicle ${vehicle.id}. Engine remains unlocked.`);
      } else {
        console.log(`[MQTT] Authentication success for vehicle ${vehicle.id}. Unlocking engine in DB...`);
        await supabase
          .from('vehicles')
          .update({ is_engine_locked: false })
          .eq('id', vehicle.id);
      }
    } else if (data.type === 'authFailure') {
      console.log(`[MQTT] Authentication failure for vehicle ${vehicle.id}. Ensure engine remains locked in DB...`);
      await supabase
        .from('vehicles')
        .update({ is_engine_locked: true })
        .eq('id', vehicle.id);
    } else if (data.type === 'commandAck') {
      console.log(`[MQTT] Command acknowledged by vehicle ${vehicle.id}: ${data.message}`);
    } else if (data.type === 'system') {
      if (data.message?.includes('rejected') || data.message?.includes('Rejected')) {
        console.log(`[MQTT] Command rejected for vehicle ${vehicle.id}: ${data.message}. DB state remains unchanged.`);
      } else if (data.message?.includes('Device rebooted. Engine unlocked state restored.') ||
                 data.message?.includes('Device rebooted with ignition ON. Engine unlocked.')) {
        console.log(`[MQTT] Boot message for vehicle ${vehicle.id}: Reconciling engine unlocked state in DB.`);
        await supabase
          .from('vehicles')
          .update({ is_engine_locked: false })
          .eq('id', vehicle.id);
      }
    }
  }

  // Forward ONLY to the owner
  emitNewAlert({
    id: insertedAlertId,
    deviceId: deviceId,
    type: data.type || 'system',
    message: data.message || 'Alert from device',
    driverId: data.driverId ?? null,
    timestamp: new Date().toISOString(),
  }, ownerId);
};

