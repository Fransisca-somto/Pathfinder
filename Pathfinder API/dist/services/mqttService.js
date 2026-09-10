"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.triggerAlert = exports.clearDeviceCache = exports.publishCommand = exports.initializeMqtt = exports.mqttClient = void 0;
const mqtt_1 = __importDefault(require("mqtt"));
const supabase_1 = require("../config/supabase");
const socketManager_1 = require("../sockets/socketManager");
const tripService_1 = require("./tripService");
const zoneService_1 = require("./zoneService");
const MQTT_BROKER_URL = process.env.MQTT_BROKER_URL || 'mqtt://broker.hivemq.com:1883';
const TELEMETRY_TOPIC = 'pathfinder/telemetry';
const ALERTS_TOPIC = 'pathfinder/alerts';
// Cache device-to-owner mappings so we don't hit the DB on every MQTT message
const deviceOwnerCache = new Map();
// Track previous status to detect trip start/end
const deviceStatusCache = new Map();
// Keep track of timeouts for each device to mark them offline after 2 minutes of silence
const deviceTimeouts = new Map();
// Keep track of overspeeding alerts to prevent spam (1 minute cooldown)
const lastOverspeedAlerts = new Map();
const OVERSPEED_THRESHOLD_KMPH = 80;
const OVERSPEED_COOLDOWN_MS = 60000;
const initializeMqtt = () => {
    console.log(`[MQTT] Connecting to broker: ${MQTT_BROKER_URL}`);
    exports.mqttClient = mqtt_1.default.connect(MQTT_BROKER_URL);
    exports.mqttClient.on('connect', () => {
        console.log('[MQTT] Connected to broker successfully!');
        // Subscribe to the topics the ESP32 publishes to
        exports.mqttClient.subscribe([TELEMETRY_TOPIC, ALERTS_TOPIC], (err) => {
            if (err) {
                console.error('[MQTT] Subscribe error:', err);
            }
            else {
                console.log(`[MQTT] Subscribed to: ${TELEMETRY_TOPIC}, ${ALERTS_TOPIC}`);
            }
        });
    });
    exports.mqttClient.on('message', (topic, message) => {
        try {
            const payload = JSON.parse(message.toString());
            console.log(`[MQTT] ${topic} =>`, payload);
            if (topic === TELEMETRY_TOPIC) {
                handleTelemetry(payload);
            }
            else if (topic === ALERTS_TOPIC) {
                (0, exports.triggerAlert)(payload);
            }
        }
        catch (err) {
            console.error('[MQTT] Failed to parse message:', message.toString());
        }
    });
    exports.mqttClient.on('error', (err) => {
        console.error('[MQTT] Connection error:', err);
    });
    exports.mqttClient.on('offline', () => {
        console.warn('[MQTT] Client went offline');
    });
    exports.mqttClient.on('reconnect', () => {
        console.log('[MQTT] Reconnecting...');
    });
};
exports.initializeMqtt = initializeMqtt;
const publishCommand = (deviceId, command, payload = {}) => {
    if (!exports.mqttClient || !exports.mqttClient.connected) {
        console.warn('[MQTT] Cannot publish command, mqttClient not connected');
        return;
    }
    const topic = 'pathfinder/commands';
    const message = JSON.stringify({
        deviceId,
        command,
        ...payload
    });
    exports.mqttClient.publish(topic, message);
    console.log(`[MQTT] Published command to ${deviceId}:`, command);
};
exports.publishCommand = publishCommand;
// Look up the owner of a device (with caching)
const getDeviceOwner = async (deviceId) => {
    // Check cache first
    if (deviceOwnerCache.has(deviceId)) {
        return deviceOwnerCache.get(deviceId);
    }
    // Query Supabase
    const { data, error } = await supabase_1.supabase
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
const resetDeviceTimeout = (deviceId, ownerId) => {
    if (deviceTimeouts.has(deviceId)) {
        clearTimeout(deviceTimeouts.get(deviceId));
    }
    const timeout = setTimeout(async () => {
        console.log(`[MQTT] Device ${deviceId} timed out after 120 seconds of silence. Marking offline.`);
        deviceTimeouts.delete(deviceId);
        // Update DB
        await supabase_1.supabase
            .from('vehicles')
            .update({ status: 'offline' })
            .ilike('device_id', deviceId);
        // Notify Flutter App
        (0, socketManager_1.emitLiveTelemetry)({
            deviceId: deviceId,
            status: 'offline',
            timestamp: new Date().toISOString(),
        }, ownerId);
    }, 120000); // 2 minutes
    deviceTimeouts.set(deviceId, timeout);
};
// Clear cache for a specific device (call this when a vehicle is registered or deleted)
const clearDeviceCache = (deviceId) => {
    deviceOwnerCache.delete(deviceId);
};
exports.clearDeviceCache = clearDeviceCache;
// Handle incoming GPS telemetry from ESP32
const handleTelemetry = async (data) => {
    const deviceId = data.deviceId?.toUpperCase();
    if (!deviceId) {
        return;
    }
    // Look up who owns this device
    const ownerId = await getDeviceOwner(deviceId);
    // Get vehicle_id for trips
    let vehicleId = '';
    if (ownerId) {
        const { data } = await supabase_1.supabase.from('vehicles').select('id').ilike('device_id', deviceId).single();
        if (data)
            vehicleId = data.id;
    }
    if (!ownerId) {
        console.warn(`[MQTT] Unclaimed device: ${deviceId} — ignoring telemetry`);
        return;
    }
    const updatePayload = {};
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
    }
    else if (data.speed !== undefined) {
        finalStatus = data.speed > 0 ? 'moving' : 'parked';
    }
    updatePayload.status = finalStatus;
    // Update the vehicle's location in the database
    await supabase_1.supabase
        .from('vehicles')
        .update(updatePayload)
        .ilike('device_id', deviceId);
    // --- TRIP TRACKING LOGIC ---
    if (vehicleId && data.lat && data.lng) {
        const prevStatus = deviceStatusCache.get(deviceId) || 'parked';
        if (prevStatus !== 'moving' && finalStatus === 'moving') {
            await (0, tripService_1.startTrip)(vehicleId, data.lat, data.lng);
        }
        else if (prevStatus === 'moving' && (finalStatus === 'parked' || finalStatus === 'offline')) {
            await (0, tripService_1.endTrip)(vehicleId, data.lat, data.lng);
        }
        else if (finalStatus === 'moving') {
            (0, tripService_1.appendTripCoordinate)(vehicleId, data.lat, data.lng);
        }
        deviceStatusCache.set(deviceId, finalStatus);
        // Evaluate against assigned zones
        await (0, zoneService_1.processVehicleLocation)(vehicleId, deviceId, data.lat, data.lng, data.acc, ownerId);
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
        temperature: data.temperature,
        status: finalStatus,
        timestamp: new Date().toISOString(),
    };
    // Forward ONLY to the owner's private WebSocket room
    console.log(`[MQTT] Forwarding telemetry for device ${deviceId} to owner ${ownerId}. Status: ${finalStatus}`);
    (0, socketManager_1.emitLiveTelemetry)(telemetryPayload, ownerId);
    if (finalStatus === 'offline') {
        if (deviceTimeouts.has(deviceId)) {
            clearTimeout(deviceTimeouts.get(deviceId));
            deviceTimeouts.delete(deviceId);
        }
    }
    else {
        resetDeviceTimeout(deviceId, ownerId);
    }
    // Check for overspeeding
    if (data.speed && data.speed > OVERSPEED_THRESHOLD_KMPH) {
        const now = Date.now();
        const lastAlertTime = lastOverspeedAlerts.get(deviceId) || 0;
        if (now - lastAlertTime > OVERSPEED_COOLDOWN_MS) {
            lastOverspeedAlerts.set(deviceId, now);
            // Trigger an alert internally
            (0, exports.triggerAlert)({
                deviceId: deviceId,
                type: 'speed',
                message: `Overspeeding detected: ${Math.round(data.speed)} km/h`,
            });
        }
    }
};
// Handle incoming alerts from ESP32 (e.g. panic button)
const triggerAlert = async (data) => {
    const deviceId = data.deviceId;
    if (!deviceId)
        return;
    const ownerId = await getDeviceOwner(deviceId);
    if (!ownerId) {
        console.warn(`[MQTT] Alert from unclaimed device: ${deviceId} — ignoring`);
        return;
    }
    console.log(`[MQTT] Alert from device ${deviceId} for owner ${ownerId}:`, data);
    // Save alert to database
    const { data: vehicle } = await supabase_1.supabase
        .from('vehicles')
        .select('id')
        .ilike('device_id', deviceId)
        .single();
    let insertedAlertId = '';
    if (vehicle) {
        const { data: newAlert } = await supabase_1.supabase.from('alerts').insert({
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
                await supabase_1.supabase
                    .from('fingerprint_profiles')
                    .update({ status: 'enrolled' })
                    .eq('vehicle_id', vehicle.id)
                    .eq('status', 'pending');
            }
            else if (data.message === 'Fingerprint enrollment timeout') {
                console.log(`[MQTT] Detected enrollment timeout for vehicle ${vehicle.id}. Cleaning up DB...`);
                await supabase_1.supabase
                    .from('fingerprint_profiles')
                    .delete()
                    .eq('vehicle_id', vehicle.id)
                    .eq('status', 'pending');
            }
        }
        else if (data.type === 'authSuccess') {
            console.log(`[MQTT] Authentication success for vehicle ${vehicle.id}. Unlocking engine in DB...`);
            await supabase_1.supabase
                .from('vehicles')
                .update({ is_engine_locked: false })
                .eq('id', vehicle.id);
        }
        else if (data.type === 'authFailure') {
            console.log(`[MQTT] Authentication failure for vehicle ${vehicle.id}. Ensure engine remains locked in DB...`);
            await supabase_1.supabase
                .from('vehicles')
                .update({ is_engine_locked: true })
                .eq('id', vehicle.id);
        }
    }
    // Forward ONLY to the owner
    (0, socketManager_1.emitNewAlert)({
        id: insertedAlertId,
        deviceId: deviceId,
        type: data.type || 'system',
        message: data.message || 'Alert from device',
        timestamp: new Date().toISOString(),
    }, ownerId);
};
exports.triggerAlert = triggerAlert;
//# sourceMappingURL=mqttService.js.map