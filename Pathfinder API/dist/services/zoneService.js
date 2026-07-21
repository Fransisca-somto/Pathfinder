"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.processVehicleLocation = exports.refreshZoneCache = exports.isPointInZone = void 0;
const supabase_1 = require("../config/supabase");
const mqttService_1 = require("./mqttService"); // We will export triggerAlert from mqttService
// Memory Cache
const zonesCache = new Map();
// Tracking vehicle states: { vehicleId: { zoneId: 'inside' | 'outside' } }
const vehicleZoneState = new Map();
// --- Math Helpers ---
const deg2rad = (deg) => deg * (Math.PI / 180);
const getDistanceFromLatLonInM = (lat1, lon1, lat2, lon2) => {
    const R = 6371e3; // Radius of the earth in m
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
};
const isPointInPolygon = (point, vs) => {
    const x = point[0], y = point[1];
    let inside = false;
    for (let i = 0, j = vs.length - 1; i < vs.length; j = i++) {
        const xi = vs[i][0], yi = vs[i][1];
        const xj = vs[j][0], yj = vs[j][1];
        const intersect = ((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
        if (intersect)
            inside = !inside;
    }
    return inside;
};
const isPointInZone = (lat, lng, zone) => {
    if (zone.shape_type === 'circle') {
        const distance = getDistanceFromLatLonInM(lat, lng, zone.center_latitude, zone.center_longitude);
        return distance <= zone.radius_meters;
    }
    else if (zone.shape_type === 'polygon' && zone.polygon_points && zone.polygon_points.length >= 3) {
        return isPointInPolygon([lat, lng], zone.polygon_points);
    }
    return false;
};
exports.isPointInZone = isPointInZone;
// --- Cache Management ---
const refreshZoneCache = async () => {
    console.log('[ZoneService] Refreshing zone cache from DB...');
    try {
        // 1. Fetch all zones
        const { data: zones, error: zoneError } = await supabase_1.supabase.from('zones').select('*');
        if (zoneError)
            throw zoneError;
        // 2. Fetch all assignments
        const { data: assignments, error: assignError } = await supabase_1.supabase.from('zone_vehicles').select('*');
        if (assignError)
            throw assignError;
        // 3. Build cache
        zonesCache.clear();
        for (const z of zones || []) {
            const assignedVehicles = new Set();
            (assignments || []).forEach(a => {
                if (a.zone_id === z.id) {
                    assignedVehicles.add(a.vehicle_id);
                }
            });
            zonesCache.set(z.id, {
                id: z.id,
                name: z.name,
                type: z.type,
                shape_type: z.shape_type,
                center_latitude: z.center_latitude,
                center_longitude: z.center_longitude,
                radius_meters: z.radius_meters,
                polygon_points: z.polygon_points || [],
                owner_id: z.owner_id,
                assigned_vehicles: assignedVehicles
            });
        }
        console.log(`[ZoneService] Cached ${zonesCache.size} zones.`);
    }
    catch (err) {
        console.error('[ZoneService] Error refreshing zone cache:', err);
    }
};
exports.refreshZoneCache = refreshZoneCache;
// Call this on backend startup
(0, exports.refreshZoneCache)();
// --- Processing Logic ---
const processVehicleLocation = async (vehicleId, deviceId, lat, lng, ownerId) => {
    if (!vehicleZoneState.has(vehicleId)) {
        vehicleZoneState.set(vehicleId, new Map());
    }
    const stateMap = vehicleZoneState.get(vehicleId);
    for (const [zoneId, zone] of zonesCache.entries()) {
        // ONLY check if the vehicle is assigned to this zone
        if (!zone.assigned_vehicles.has(vehicleId))
            continue;
        const isInsideNow = (0, exports.isPointInZone)(lat, lng, zone);
        const wasInsideBefore = stateMap.get(zoneId) === 'inside';
        if (isInsideNow && !wasInsideBefore) {
            // Transition: OUTSIDE -> INSIDE
            stateMap.set(zoneId, 'inside');
            console.log(`[ZoneService] Vehicle ${deviceId} ENTERED zone ${zone.name}`);
            if (zone.type === 'restricted') {
                // Automatically lock engine!
                console.log(`[ZoneService] Restricted zone entered. LOCKING ENGINE for ${deviceId}!`);
                await supabase_1.supabase.from('vehicles').update({ is_engine_locked: true }).eq('id', vehicleId);
                (0, mqttService_1.publishCommand)(deviceId, 'LOCK_ENGINE');
                (0, mqttService_1.triggerAlert)({
                    deviceId,
                    type: 'zoneEnter',
                    message: `UNSAFE ZONE ENTRY: Vehicle entered '${zone.name}'. ENGINE DISABLED automatically.`
                });
            }
            else {
                (0, mqttService_1.triggerAlert)({
                    deviceId,
                    type: 'zoneEnter',
                    message: `Vehicle entered zone: ${zone.name}`
                });
            }
        }
        else if (!isInsideNow && wasInsideBefore) {
            // Transition: INSIDE -> OUTSIDE
            stateMap.set(zoneId, 'outside');
            console.log(`[ZoneService] Vehicle ${deviceId} EXITED zone ${zone.name}`);
            if (zone.type === 'safe') {
                (0, mqttService_1.triggerAlert)({
                    deviceId,
                    type: 'zoneExit',
                    message: `WARNING: Vehicle exited safe zone: ${zone.name}`
                });
            }
            else {
                (0, mqttService_1.triggerAlert)({
                    deviceId,
                    type: 'zoneExit',
                    message: `Vehicle exited zone: ${zone.name}`
                });
            }
        }
    }
};
exports.processVehicleLocation = processVehicleLocation;
//# sourceMappingURL=zoneService.js.map