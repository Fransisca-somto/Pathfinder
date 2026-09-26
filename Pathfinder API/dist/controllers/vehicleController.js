"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.setEmergencyContact = exports.getTrips = exports.assignDriver = exports.updateVehicle = exports.deleteVehicle = exports.getVehicleById = exports.getVehicles = exports.registerVehicle = exports.soundAlarm = exports.setAuthBypass = exports.toggleFingerprintStatus = exports.deleteFingerprint = exports.addFingerprint = exports.getFingerprints = void 0;
const supabase_1 = require("../config/supabase");
const mqttService_1 = require("../services/mqttService");
// ---------------------------------------------------------------------------
// Access-check helper
// ---------------------------------------------------------------------------
// Verifies a user has access to a vehicle via the vehicle_users join table.
// Returns the vehicle row (plus any extra columns in selectCols) or null.
// Every endpoint uses this instead of the old .eq('owner_id', userId) pattern.
const checkVehicleAccess = async (vehicleId, userId, selectCols = 'id') => {
    const { data } = await supabase_1.supabase
        .from('vehicles')
        .select(`${selectCols}, vehicle_users!inner(user_id)`)
        .eq('id', vehicleId)
        .eq('vehicle_users.user_id', userId)
        .single();
    return data ?? null;
};
// GET /vehicles/:id/fingerprints
const getFingerprints = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const vehicle = await checkVehicleAccess(vehicleId, userId);
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        const { data, error } = await supabase_1.supabase
            .from('fingerprint_profiles')
            .select('*')
            .eq('vehicle_id', vehicleId)
            .order('slot_id', { ascending: true });
        if (error) {
            console.error('[Vehicle] Fetch fingerprints error:', error);
            res.status(500).json({ error: 'Failed to fetch fingerprints' });
            return;
        }
        res.status(200).json(data);
    }
    catch (err) {
        console.error('[Vehicle] Fetch fingerprints error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getFingerprints = getFingerprints;
// POST /vehicles/:id/fingerprints (Adds to DB and triggers ESP32 enrollment)
const addFingerprint = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const { driverName } = req.body;
        if (!driverName) {
            res.status(400).json({ error: 'driverName is required' });
            return;
        }
        console.log(`[DEBUG] POST /vehicles/${vehicleId}/fingerprints - userId: ${userId}`);
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        // Find the next available Slot ID (1 to 127)
        const { data: existingProfiles } = await supabase_1.supabase
            .from('fingerprint_profiles')
            .select('slot_id')
            .eq('vehicle_id', vehicleId);
        const usedSlots = new Set(existingProfiles?.map(p => p.slot_id) || []);
        let nextSlotId = 1;
        while (usedSlots.has(nextSlotId) && nextSlotId <= 127) {
            nextSlotId++;
        }
        if (nextSlotId > 127) {
            res.status(400).json({ error: 'Maximum of 127 fingerprints reached.' });
            return;
        }
        // Insert into DB with status pending
        const { error } = await supabase_1.supabase
            .from('fingerprint_profiles')
            .insert({
            vehicle_id: vehicleId,
            driver_name: driverName,
            slot_id: nextSlotId,
            status: 'pending'
        });
        if (error) {
            console.error('[Vehicle] Failed to insert profile:', error);
            res.status(500).json({ error: error.message || 'Failed to insert profile', details: error.details, hint: error.hint });
            return;
        }
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'enrollFingerprint', { driverId: nextSlotId });
        res.status(200).json({ message: 'Profile saved and enrollment command sent to vehicle', slotId: nextSlotId });
    }
    catch (err) {
        console.error('[Vehicle] Add fingerprint error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.addFingerprint = addFingerprint;
// DELETE /vehicles/:id/fingerprints/:slotId
const deleteFingerprint = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const slotId = parseInt(req.params.slotId);
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        const { error } = await supabase_1.supabase
            .from('fingerprint_profiles')
            .delete()
            .eq('vehicle_id', vehicleId)
            .eq('slot_id', slotId);
        if (error) {
            res.status(500).json({ error: 'Failed to delete fingerprint profile' });
            return;
        }
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'deleteFingerprint', { driverId: slotId });
        res.status(200).json({ message: 'Fingerprint deleted successfully' });
    }
    catch (err) {
        console.error('[Vehicle] Delete fingerprint error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.deleteFingerprint = deleteFingerprint;
// POST /vehicles/:id/fingerprints/:slotId/toggle
const toggleFingerprintStatus = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const slotId = parseInt(req.params.slotId);
        const { isActive } = req.body;
        if (typeof isActive !== 'boolean') {
            res.status(400).json({ error: 'isActive boolean is required' });
            return;
        }
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        // Update the database
        const { error } = await supabase_1.supabase
            .from('fingerprint_profiles')
            .update({ is_active: isActive })
            .eq('vehicle_id', vehicleId)
            .eq('slot_id', slotId);
        if (error) {
            res.status(500).json({ error: 'Failed to update fingerprint profile status' });
            return;
        }
        // Send command to ESP32
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'setDriverStatus', { driverId: slotId, isActive });
        res.status(200).json({ message: `Fingerprint ${isActive ? 'activated' : 'deactivated'} successfully` });
    }
    catch (err) {
        console.error('[Vehicle] Toggle fingerprint status error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.toggleFingerprintStatus = toggleFingerprintStatus;
// POST /vehicles/:id/auth-bypass
const setAuthBypass = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const { state } = req.body; // boolean
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        const isBypassOn = !!state;
        // When bypass is ON, engine is unlocked. When OFF, engine is locked.
        await supabase_1.supabase
            .from('vehicles')
            .update({ is_engine_locked: !isBypassOn })
            .eq('id', vehicleId);
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'setAuthBypass', { state: isBypassOn });
        res.status(200).json({ message: 'Auth bypass command sent to vehicle' });
    }
    catch (err) {
        console.error('[Vehicle] Set auth bypass error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.setAuthBypass = setAuthBypass;
// POST /vehicles/:id/alarm
const soundAlarm = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const { state } = req.body; // boolean
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        const isAlarmOn = !!state;
        await supabase_1.supabase
            .from('vehicles')
            .update({ is_alarm_active: isAlarmOn })
            .eq('id', vehicleId);
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'soundAlarm', { state: isAlarmOn });
        res.status(200).json({ message: 'Alarm command sent to vehicle' });
    }
    catch (err) {
        console.error('[Vehicle] Sound alarm error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.soundAlarm = soundAlarm;
// POST /vehicles/register — Claim a device by its ID
const registerVehicle = async (req, res) => {
    try {
        const { name, plateNumber, type } = req.body;
        const deviceId = req.body.deviceId?.toUpperCase();
        const userId = req.user.id;
        if (!deviceId || !name || !plateNumber) {
            res.status(400).json({ error: 'deviceId, name, and plateNumber are required' });
            return;
        }
        // TODO: SECURITY — Replace this open-claim flow with an invitation or approval
        // flow before any non-team users access the system. Knowing a device ID is
        // currently sufficient to gain full control of someone's vehicle immobiliser,
        // including live location tracking, engine lock/unlock, and alarm control.
        // Ensure the claiming user exists in public.users before touching vehicle_users.
        // The auth trigger should create this row on signup, but it can be missing for
        // accounts created before the trigger was installed or via the Supabase dashboard.
        // We check explicitly and insert only when needed so we always see the real error.
        const { data: existingUserRow } = await supabase_1.supabase
            .from('users')
            .select('id')
            .eq('id', userId)
            .single();
        if (!existingUserRow) {
            // Validate role against the user_role enum — anything outside this set
            // causes a silent upsert failure which then surfaces as an FK error later.
            const VALID_ROLES = ['owner', 'manager', 'driver'];
            const rawRole = req.user.user_metadata?.role;
            const safeRole = VALID_ROLES.includes(rawRole) ? rawRole : 'owner';
            const { error: createUserError } = await supabase_1.supabase.from('users').insert({
                id: userId,
                email: req.user.email ?? '',
                full_name: req.user.user_metadata?.full_name ?? req.user.email?.split('@')[0] ?? 'User',
                role: safeRole,
            });
            if (createUserError) {
                console.error('[Vehicle] Failed to create public.users row for authenticated user:', createUserError);
                res.status(500).json({ error: 'Failed to set up user profile. Please try again.' });
                return;
            }
            console.log(`[Vehicle] Created missing public.users row for ${userId}`);
        }
        // Check if this device is already registered
        const { data: existing } = await supabase_1.supabase
            .from('vehicles')
            .select('id')
            .ilike('device_id', deviceId)
            .single();
        if (existing) {
            // Device already exists — add the calling user to vehicle_users.
            // If they already have access, the PRIMARY KEY constraint fires (code 23505).
            const { error: linkError } = await supabase_1.supabase
                .from('vehicle_users')
                .insert({ vehicle_id: existing.id, user_id: userId, role: 'owner' });
            if (linkError?.code === '23505') {
                res.status(409).json({ error: 'You already have access to this device' });
                return;
            }
            if (linkError) {
                console.error('[Vehicle] Failed to link user to existing vehicle:', linkError);
                res.status(500).json({ error: 'Failed to claim device' });
                return;
            }
            // Update vehicle data with what the new claimer provided so a re-registration
            // (after a previous user deleted their access) always reflects fresh data.
            const { data: vehicle, error: updateError } = await supabase_1.supabase
                .from('vehicles')
                .update({
                name,
                plate_number: plateNumber,
                type: type || 'Car',
            })
                .eq('id', existing.id)
                .select()
                .single();
            if (updateError) {
                console.error('[Vehicle] Failed to update vehicle data on re-claim:', updateError);
            }
            // Invalidate the MQTT users cache so the new claimant starts receiving telemetry
            (0, mqttService_1.clearDeviceCache)(deviceId);
            console.log(`[Vehicle] Device ${deviceId} claimed by user ${userId} — vehicle data updated`);
            res.status(200).json({ message: 'Device claimed successfully', vehicle });
            return;
        }
        // First claim — insert the vehicle row and link the user
        const { data, error } = await supabase_1.supabase
            .from('vehicles')
            .insert({
            device_id: deviceId,
            name,
            plate_number: plateNumber,
            type: type || 'Car',
            owner_id: userId, // kept for audit trail and existing RLS policies
            status: 'offline',
        })
            .select()
            .single();
        if (error || !data) {
            console.error('[Vehicle] Register error:', error);
            res.status(500).json({ error: 'Failed to register vehicle' });
            return;
        }
        // Link the first claimer into vehicle_users
        await supabase_1.supabase
            .from('vehicle_users')
            .insert({ vehicle_id: data.id, user_id: userId, role: 'owner' });
        console.log(`[Vehicle] Device ${deviceId} registered and claimed by user ${userId}`);
        res.status(201).json({ message: 'Vehicle registered successfully', vehicle: data });
    }
    catch (err) {
        console.error('[Vehicle] Register error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.registerVehicle = registerVehicle;
// GET /vehicles — List every vehicle the authenticated user is linked to
const getVehicles = async (req, res) => {
    try {
        const userId = req.user.id;
        // Query through vehicle_users so every claimant sees the vehicle,
        // not only the original owner_id holder.
        const { data: links, error } = await supabase_1.supabase
            .from('vehicle_users')
            .select('vehicles(*, vehicle_drivers(users(id, full_name)))')
            .eq('user_id', userId);
        if (error) {
            console.error('[Vehicle] Fetch error:', error);
            res.status(500).json({ error: 'Failed to fetch vehicles' });
            return;
        }
        // Flatten and map vehicle_drivers -> drivers
        const vehicles = (links ?? [])
            .map((link) => {
            const v = link.vehicles;
            if (!v)
                return null;
            if (v.vehicle_drivers) {
                v.drivers = v.vehicle_drivers.map((vd) => ({
                    id: vd.users?.id,
                    fullName: vd.users?.full_name
                }));
                delete v.vehicle_drivers;
            }
            else {
                v.drivers = [];
            }
            return v;
        })
            .filter(Boolean);
        res.status(200).json(vehicles);
    }
    catch (err) {
        console.error('[Vehicle] Fetch error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getVehicles = getVehicles;
// GET /vehicles/:id — Get a single vehicle (only if user has access)
const getVehicleById = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const vehicle = await checkVehicleAccess(vehicleId, userId, '*, vehicle_drivers(users(id, full_name))');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        if (vehicle.vehicle_drivers) {
            vehicle.drivers = vehicle.vehicle_drivers.map((vd) => ({
                id: vd.users?.id,
                fullName: vd.users?.full_name
            }));
            delete vehicle.vehicle_drivers;
        }
        else {
            vehicle.drivers = [];
        }
        res.status(200).json(vehicle);
    }
    catch (err) {
        console.error('[Vehicle] Fetch error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getVehicleById = getVehicleById;
// DELETE /vehicles/:id — Remove the calling user's access.
// If they were the last linked user, the vehicle row is also deleted.
const deleteVehicle = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found or you do not have access' });
            return;
        }
        // Remove this user's link only
        const { error: unlinkError } = await supabase_1.supabase
            .from('vehicle_users')
            .delete()
            .eq('vehicle_id', vehicleId)
            .eq('user_id', userId);
        if (unlinkError) {
            console.error('[Vehicle] Unlink error:', unlinkError);
            res.status(500).json({ error: 'Failed to remove vehicle access' });
            return;
        }
        // Check whether any users are still linked
        const { count } = await supabase_1.supabase
            .from('vehicle_users')
            .select('*', { count: 'exact', head: true })
            .eq('vehicle_id', vehicleId);
        if (count === 0) {
            // Last user removed — delete the vehicle row entirely
            const { error: deleteError } = await supabase_1.supabase
                .from('vehicles')
                .delete()
                .eq('id', vehicleId);
            if (deleteError) {
                console.error('[Vehicle] Delete error:', deleteError);
                res.status(500).json({ error: 'Failed to delete vehicle' });
                return;
            }
            console.log(`[Vehicle] Device ${vehicle.device_id} fully deleted — no remaining users`);
        }
        else {
            console.log(`[Vehicle] User ${userId} unlinked from device ${vehicle.device_id} (${count} user(s) remaining)`);
        }
        // Invalidate MQTT cache so the departed user stops receiving telemetry
        (0, mqttService_1.clearDeviceCache)(vehicle.device_id);
        res.status(200).json({ message: 'Vehicle removed successfully' });
    }
    catch (err) {
        console.error('[Vehicle] Delete error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.deleteVehicle = deleteVehicle;
// PUT /vehicles/:id — Update vehicle settings
const updateVehicle = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const { name, plate_number, type, update_interval, connection_mode } = req.body;
        const access = await checkVehicleAccess(vehicleId, userId);
        if (!access) {
            res.status(404).json({ error: 'Vehicle not found or you do not have access' });
            return;
        }
        const { data, error } = await supabase_1.supabase
            .from('vehicles')
            .update({ name, plate_number, type, update_interval, connection_mode })
            .eq('id', vehicleId)
            .select()
            .single();
        if (error) {
            console.error('[Vehicle] Update error:', error);
            res.status(500).json({ error: 'Failed to update vehicle settings' });
            return;
        }
        res.status(200).json({ message: 'Vehicle settings updated', vehicle: data });
    }
    catch (err) {
        console.error('[Vehicle] Update error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.updateVehicle = updateVehicle;
// POST /vehicles/:id/drivers — Assign a driver to a vehicle by email
const assignDriver = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const { email } = req.body;
        if (!email) {
            res.status(400).json({ error: 'Driver email is required' });
            return;
        }
        const access = await checkVehicleAccess(vehicleId, userId);
        if (!access) {
            res.status(404).json({ error: 'Vehicle not found or you do not have access' });
            return;
        }
        // 1. Check if the user already exists in public.users
        let { data: existingUser } = await supabase_1.supabase
            .from('users')
            .select('id')
            .eq('email', email.toLowerCase())
            .single();
        let driverId = existingUser?.id;
        // 2. If user doesn't exist, create an account for them
        if (!driverId) {
            const defaultPassword = 'DriverPassword123!'; // We'll assume the driver can reset this later
            const { data: authData, error: authError } = await supabase_1.supabase.auth.signUp({
                email: email.toLowerCase(),
                password: defaultPassword,
                options: {
                    data: {
                        full_name: 'Fleet Driver',
                        role: 'driver'
                    }
                }
            });
            if (authError || !authData.user) {
                console.error('[Vehicle] Failed to create driver auth:', authError);
                res.status(400).json({ error: 'Failed to create driver account. Is the email valid?' });
                return;
            }
            driverId = authData.user.id;
            // Insert into public.users
            await supabase_1.supabase.from('users').insert({
                id: driverId,
                email: email.toLowerCase(),
                full_name: 'Fleet Driver',
                role: 'driver'
            });
        }
        // 3. Link driver to the vehicle in vehicle_drivers table
        const { error: linkError } = await supabase_1.supabase
            .from('vehicle_drivers')
            .insert({
            vehicle_id: vehicleId,
            user_id: driverId
        });
        // Handle case where they are already assigned (Unique constraint violation)
        if (linkError && linkError.code !== '23505') {
            console.error('[Vehicle] Failed to link driver:', linkError);
            res.status(500).json({ error: 'Failed to assign driver to vehicle' });
            return;
        }
        res.status(200).json({ message: 'Driver assigned successfully', driverId });
    }
    catch (err) {
        console.error('[Vehicle] Assign driver error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.assignDriver = assignDriver;
// GET /vehicles/:id/trips — Get history of trips for a vehicle
const getTrips = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        const access = await checkVehicleAccess(vehicleId, userId);
        if (!access) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        const { data, error } = await supabase_1.supabase
            .from('trips')
            .select('*')
            .eq('vehicle_id', vehicleId)
            .order('start_time', { ascending: false });
        if (error) {
            console.error('[Trip] Fetch error:', error);
            res.status(500).json({ error: 'Failed to fetch trips' });
            return;
        }
        res.status(200).json(data);
    }
    catch (err) {
        console.error('[Trip] Fetch error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.getTrips = getTrips;
// POST /vehicles/:id/emergency-contact
const setEmergencyContact = async (req, res) => {
    try {
        const userId = req.user.id;
        const vehicleId = req.params.id;
        let { phoneNumber } = req.body;
        if (!phoneNumber) {
            res.status(400).json({ error: 'phoneNumber is required' });
            return;
        }
        // Normalize phone number
        phoneNumber = phoneNumber.replace(/[^0-9+]/g, '');
        if (phoneNumber.startsWith('0')) {
            phoneNumber = '+234' + phoneNumber.substring(1);
        }
        else if (!phoneNumber.startsWith('+')) {
            phoneNumber = '+' + phoneNumber;
        }
        if (phoneNumber.length < 7 || phoneNumber.length > 19) {
            res.status(400).json({ error: 'Invalid phone number format' });
            return;
        }
        const vehicle = await checkVehicleAccess(vehicleId, userId, 'id, device_id');
        if (!vehicle) {
            res.status(404).json({ error: 'Vehicle not found' });
            return;
        }
        // Save to database
        const { error } = await supabase_1.supabase
            .from('vehicles')
            .update({ emergency_contact: phoneNumber })
            .eq('id', vehicleId);
        if (error) {
            res.status(500).json({ error: 'Failed to update emergency contact' });
            return;
        }
        // Publish command
        (0, mqttService_1.publishCommand)(vehicle.device_id, 'setEmergencyContact', { phone: phoneNumber });
        res.status(200).json({ message: 'Emergency contact updated successfully', emergencyContact: phoneNumber });
    }
    catch (err) {
        console.error('[Vehicle] Set emergency contact error:', err);
        res.status(500).json({ error: 'Internal server error' });
    }
};
exports.setEmergencyContact = setEmergencyContact;
//# sourceMappingURL=vehicleController.js.map