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
const STATUS_TOPIC = 'pathfinder/status';
// Cache device-to-owner mappings so we don't hit the DB on every MQTT message
const deviceOwnerCache = new Map();
// Track previous status to detect trip start/end
const deviceStatusCache = new Map();
// Keep track of timeouts for each device to mark them offline after 2 minutes of silence
const deviceTimeouts = new Map();
// Track last telemetry time to override stale LWT messages
const lastTelemetryTimes = new Map();
// Track when a device started moving to prevent jitter-based phantom trips
const deviceMovingSince = new Map();
// Track when a moving device lost its GPS fix (for the 5-minute pause before ending trip)
const deviceNoFixSince = new Map();
// Keep track of overspeeding alerts to prevent spam (1 minute cooldown)
const lastOverspeedAlerts = new Map();
const OVERSPEED_THRESHOLD_KMPH = 80;
const OVERSPEED_COOLDOWN_MS = 60000;
// Deduplication cache for SD-card-queued and re-sent alerts.
// Key: "deviceId|type|message|uptime" — Value: timestamp when cached.
// Entries auto-expire after 60 seconds via setTimeout.
const alertDedupeCache = new Map();
const ALERT_DEDUPE_TTL_MS = 60000;
const initializeMqtt = () => {
    console.log(`[MQTT] Connecting to broker: ${MQTT_BROKER_URL}`);
    exports.mqttClient = mqtt_1.default.connect(MQTT_BROKER_URL);
    exports.mqttClient.on('connect', () => {
        console.log('[MQTT] Connected to broker successfully!');
        // Subscribe to the topics the ESP32 publishes to
        exports.mqttClient.subscribe([TELEMETRY_TOPIC, ALERTS_TOPIC, STATUS_TOPIC], (err) => {
            if (err) {
                console.error('[MQTT] Subscribe error:', err);
            }
            else {
                console.log(`[MQTT] Subscribed to: ${TELEMETRY_TOPIC}, ${ALERTS_TOPIC}, ${STATUS_TOPIC}`);
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
            else if (topic === STATUS_TOPIC) {
                handleStatus(payload);
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
        deviceId: deviceId.toLowerCase(),
        command,
        payload
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
// Mark a device offline explicitly
const markDeviceOffline = async (deviceId, ownerId) => {
    console.log(`[MQTT] Device ${deviceId} is now offline.`);
    if (deviceTimeouts.has(deviceId)) {
        clearTimeout(deviceTimeouts.get(deviceId));
        deviceTimeouts.delete(deviceId);
    }
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
};
// Reset the 120-second offline timeout for a device
const resetDeviceTimeout = (deviceId, ownerId) => {
    if (deviceTimeouts.has(deviceId)) {
        clearTimeout(deviceTimeouts.get(deviceId));
    }
    const timeout = setTimeout(() => {
        console.log(`[MQTT] Device ${deviceId} timed out after 120 seconds of silence.`);
        markDeviceOffline(deviceId, ownerId);
    }, 120000); // 2 minutes
    deviceTimeouts.set(deviceId, timeout);
};
// Clear cache for a specific device (call this when a vehicle is registered or deleted)
const clearDeviceCache = (deviceId) => {
    deviceOwnerCache.delete(deviceId);
};
exports.clearDeviceCache = clearDeviceCache;
// Handle explicit LWT / status messages
const handleStatus = async (data) => {
    const deviceId = data.deviceId?.toUpperCase();
    if (!deviceId)
        return;
    const ownerId = await getDeviceOwner(deviceId);
    if (!ownerId)
        return;
    if (data.status === 'offline') {
        const lastTime = lastTelemetryTimes.get(deviceId) || 0;
        if (Date.now() - lastTime < 30000) {
            console.log(`[MQTT] Ignoring stale offline status for ${deviceId}, telemetry received recently`);
            return;
        }
        await markDeviceOffline(deviceId, ownerId);
    }
    else if (data.status === 'online') {
        console.log(`[MQTT] Device ${deviceId} reported online. Marking as parked.`);
        if (deviceTimeouts.has(deviceId)) {
            clearTimeout(deviceTimeouts.get(deviceId));
            deviceTimeouts.delete(deviceId);
        }
        // Immediately persist online (parked) status
        await supabase_1.supabase
            .from('vehicles')
            .update({ status: 'parked' })
            .ilike('device_id', deviceId);
        // Notify Flutter App
        (0, socketManager_1.emitLiveTelemetry)({
            deviceId: deviceId,
            status: 'parked',
            timestamp: new Date().toISOString(),
        }, ownerId);
    }
};
// Handle incoming GPS telemetry from ESP32
const handleTelemetry = async (data) => {
    const deviceId = data.deviceId?.toUpperCase();
    if (!deviceId) {
        return;
    }
    lastTelemetryTimes.set(deviceId, Date.now());
    // --- TELEMETRY VALIDATION ---
    const hasGpsFix = data.gps_fix !== false;
    if (hasGpsFix) {
        if (data.satellites !== undefined && data.satellites > 32) {
            console.warn(`[MQTT] Rejecting telemetry for ${deviceId}: Impossible satellite count (${data.satellites})`);
            return;
        }
        if (data.lat !== undefined && data.lng !== undefined && data.lat !== null && data.lng !== null) {
            if (Math.abs(data.lat) < 1.0 && Math.abs(data.lng) < 1.0) {
                console.warn(`[MQTT] Rejecting telemetry for ${deviceId}: Coordinates near Null Island (${data.lat}, ${data.lng})`);
                return;
            }
        }
    }
    // ----------------------------
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
    updatePayload.gps_fix = hasGpsFix;
    updatePayload.fix_age_s = data.fix_age_s ?? 0;
    if (hasGpsFix && data.lat !== undefined && data.lng !== undefined && data.lat !== null && data.lng !== null) {
        updatePayload.current_latitude = data.lat;
        updatePayload.current_longitude = data.lng;
        updatePayload.last_known_location = `${data.lat}, ${data.lng}`;
    }
    else if (!hasGpsFix && data.last_lat !== undefined && data.last_lng !== undefined && data.last_lat !== null && data.last_lng !== null) {
        // Keep the most recent known position without overwriting with null
        updatePayload.current_latitude = data.last_lat;
        updatePayload.current_longitude = data.last_lng;
        updatePayload.last_known_location = `${data.last_lat}, ${data.last_lng}`;
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
    if (data.status && data.status !== 'online') {
        finalStatus = data.status;
    }
    else if (data.speed !== undefined) {
        // 10 km/h threshold for moving
        finalStatus = data.speed > 10 ? 'moving' : 'parked';
    }
    updatePayload.status = finalStatus;
    // Update the vehicle's location in the database
    await supabase_1.supabase
        .from('vehicles')
        .update(updatePayload)
        .ilike('device_id', deviceId);
    // --- TRIP TRACKING LOGIC ---
    if (vehicleId) {
        const prevStatus = deviceStatusCache.get(deviceId) || 'parked';
        // Only use coordinates if we have a fix. Otherwise, we can't record the path.
        const hasValidCoords = hasGpsFix && data.lat !== undefined && data.lng !== undefined && data.lat !== null && data.lng !== null;
        if (!hasGpsFix && prevStatus === 'moving') {
            // Pause trip logic: Track how long we've been without a fix
            const noFixSince = deviceNoFixSince.get(deviceId) || Date.now();
            deviceNoFixSince.set(deviceId, noFixSince);
            if (Date.now() - noFixSince >= 300000) { // 5 minutes (300,000 ms)
                console.log(`[MQTT] Device ${deviceId} no fix for 5 minutes. Ending trip.`);
                await (0, tripService_1.endTrip)(vehicleId, data.last_lat ?? updatePayload.current_latitude, data.last_lng ?? updatePayload.current_longitude);
                deviceNoFixSince.delete(deviceId);
                deviceMovingSince.delete(deviceId);
                deviceStatusCache.set(deviceId, 'parked');
            }
            // If < 5 mins, do nothing (keep it 'moving' conceptually but don't append points)
        }
        else {
            // We have a fix (or were already parked) - clear the no-fix timer
            deviceNoFixSince.delete(deviceId);
            if (prevStatus !== 'moving' && finalStatus === 'moving' && hasValidCoords) {
                const movingSince = deviceMovingSince.get(deviceId) || Date.now();
                deviceMovingSince.set(deviceId, movingSince);
                if (Date.now() - movingSince >= 10000) { // 10s hysteresis
                    await (0, tripService_1.startTrip)(vehicleId, data.lat, data.lng);
                    deviceMovingSince.delete(deviceId);
                    deviceStatusCache.set(deviceId, 'moving');
                }
                else {
                    // Keep as parked internally until hysteresis passes
                    deviceStatusCache.set(deviceId, prevStatus);
                }
            }
            else if (prevStatus === 'moving' && (finalStatus === 'parked' || finalStatus === 'offline')) {
                await (0, tripService_1.endTrip)(vehicleId, data.lat ?? updatePayload.current_latitude, data.lng ?? updatePayload.current_longitude);
                deviceMovingSince.delete(deviceId);
                deviceStatusCache.set(deviceId, finalStatus);
            }
            else if (prevStatus === 'moving' && finalStatus === 'moving' && hasValidCoords) {
                (0, tripService_1.appendTripCoordinate)(vehicleId, data.lat, data.lng);
                deviceStatusCache.set(deviceId, finalStatus);
            }
            else {
                deviceMovingSince.delete(deviceId);
                deviceStatusCache.set(deviceId, finalStatus);
            }
        }
        // Evaluate against assigned zones (only if we have a real fix)
        if (hasValidCoords) {
            await (0, zoneService_1.processVehicleLocation)(vehicleId, deviceId, data.lat, data.lng, data.acc, ownerId);
        }
    }
    // ---------------------------
    // Build the telemetry payload
    const telemetryPayload = {
        deviceId: deviceId,
        lat: data.lat ?? data.last_lat,
        lng: data.lng ?? data.last_lng,
        speed: data.speed,
        acc: data.acc,
        battery: data.battery,
        battery_voltage: data.battery_voltage,
        charging: data.charging ?? false,
        power_cut: data.power_cut ?? false,
        driverId: data.driverId ?? -1,
        temperature: data.temperature,
        status: finalStatus,
        gps_fix: hasGpsFix,
        fix_age_s: data.fix_age_s ?? 0,
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
            await supabase_1.supabase
                .from('fingerprint_profiles')
                .update({ status: 'enrolled', enrolled_at: new Date().toISOString() })
                .eq('vehicle_id', vehicle.id)
                .eq('status', 'pending');
        }
        // Enrollment failed / timed out — delete the orphaned pending profile
        else if (data.type === 'enrollFailed') {
            console.log(`[MQTT] Enrollment failed for vehicle ${vehicle.id}. Cleaning up pending profile...`);
            await supabase_1.supabase
                .from('fingerprint_profiles')
                .delete()
                .eq('vehicle_id', vehicle.id)
                .eq('status', 'pending');
        }
        else if (data.type === 'authSuccess') {
            const isReAuth = data.message?.includes('re-authenticated');
            if (isReAuth) {
                console.log(`[MQTT] Driver re-authenticated for vehicle ${vehicle.id}. Engine remains unlocked.`);
            }
            else {
                console.log(`[MQTT] Authentication success for vehicle ${vehicle.id}. Unlocking engine in DB...`);
                await supabase_1.supabase
                    .from('vehicles')
                    .update({ is_engine_locked: false })
                    .eq('id', vehicle.id);
            }
        }
        else if (data.type === 'authFailure') {
            console.log(`[MQTT] Authentication failure for vehicle ${vehicle.id}. Ensure engine remains locked in DB...`);
            await supabase_1.supabase
                .from('vehicles')
                .update({ is_engine_locked: true })
                .eq('id', vehicle.id);
        }
        else if (data.type === 'commandAck') {
            console.log(`[MQTT] Command acknowledged by vehicle ${vehicle.id}: ${data.message}`);
        }
        else if (data.type === 'system') {
            if (data.message?.includes('rejected') || data.message?.includes('Rejected')) {
                console.log(`[MQTT] Command rejected for vehicle ${vehicle.id}: ${data.message}. DB state remains unchanged.`);
            }
            else if (data.message?.includes('Device rebooted. Engine unlocked state restored.') ||
                data.message?.includes('Device rebooted with ignition ON. Engine unlocked.')) {
                console.log(`[MQTT] Boot message for vehicle ${vehicle.id}: Reconciling engine unlocked state in DB.`);
                await supabase_1.supabase
                    .from('vehicles')
                    .update({ is_engine_locked: false })
                    .eq('id', vehicle.id);
            }
        }
    }
    // Forward ONLY to the owner
    (0, socketManager_1.emitNewAlert)({
        id: insertedAlertId,
        deviceId: deviceId,
        type: data.type || 'system',
        message: data.message || 'Alert from device',
        driverId: data.driverId ?? null,
        timestamp: new Date().toISOString(),
    }, ownerId);
};
exports.triggerAlert = triggerAlert;
//# sourceMappingURL=mqttService.js.map