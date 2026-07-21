import { Request, Response } from 'express';
import { supabase } from '../config/supabase';
import { publishCommand } from '../services/mqttService';
import { emitNewAlert } from '../sockets/socketManager';

// GET /vehicles/:id/fingerprints
export const getFingerprints = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;

    // Verify ownership
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    const { data, error } = await supabase
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
  } catch (err) {
    console.error('[Vehicle] Fetch fingerprints error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /vehicles/:id/fingerprints (Adds to DB and triggers ESP32 enrollment)
export const addFingerprint = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const { driverName } = req.body;

    if (!driverName) {
      res.status(400).json({ error: 'driverName is required' });
      return;
    }

    console.log(`[DEBUG] POST /vehicles/${vehicleId}/fingerprints - ownerId: ${ownerId}`);

    const { data: vehicle, error: vehicleErr } = await supabase
      .from('vehicles')
      .select('device_id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (vehicleErr) {
      console.log(`[DEBUG] Vehicle query error:`, vehicleErr);
    }

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    // Find the next available Slot ID (1 to 127)
    const { data: existingProfiles } = await supabase
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
    const { error } = await supabase
      .from('fingerprint_profiles')
      .insert({
        vehicle_id: vehicleId,
        driver_name: driverName,
        slot_id: nextSlotId,
        status: 'pending'
      });

    if (error) {
      res.status(500).json({ error: 'Failed to insert profile' });
      return;
    }

    publishCommand(vehicle.device_id, 'enrollFingerprint', { driverId: nextSlotId });
    
    // Software Fallback Timeout (65 seconds)
    setTimeout(async () => {
      try {
        const { data: profile } = await supabase
          .from('fingerprint_profiles')
          .select('status')
          .eq('vehicle_id', vehicleId)
          .eq('slot_id', nextSlotId)
          .single();
          
        if (profile && profile.status === 'pending') {
          console.log(`[Backend Timeout] Slot ${nextSlotId} for vehicle ${vehicleId} is still pending after 65s. Deleting...`);
          await supabase
            .from('fingerprint_profiles')
            .delete()
            .eq('vehicle_id', vehicleId)
            .eq('slot_id', nextSlotId);
            
          // Notify the frontend
          emitNewAlert({
            id: `timeout-${Date.now()}`,
            deviceId: vehicle.device_id,
            type: 'system',
            message: 'Fingerprint enrollment timeout',
            timestamp: new Date().toISOString()
          }, ownerId);
        }
      } catch (err) {
        console.error('[Backend Timeout] Error cleaning up pending profile:', err);
      }
    }, 65000);
    
    res.status(200).json({ message: 'Profile saved and enrollment command sent to vehicle' });
  } catch (err) {
    console.error('[Vehicle] Add fingerprint error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// DELETE /vehicles/:id/fingerprints/:driverId
export const deleteFingerprint = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const slotId = parseInt(req.params.slotId as string);

    // Verify ownership
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('device_id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    const { error } = await supabase
      .from('fingerprint_profiles')
      .delete()
      .eq('vehicle_id', vehicleId)
      .eq('slot_id', slotId);

    if (error) {
      res.status(500).json({ error: 'Failed to delete fingerprint profile' });
      return;
    }

    publishCommand(vehicle.device_id, 'deleteFingerprint', { driverId: slotId });
    
    res.status(200).json({ message: 'Fingerprint deleted successfully' });
  } catch (err) {
    console.error('[Vehicle] Delete fingerprint error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /vehicles/:id/fingerprints/:slotId/toggle
export const toggleFingerprintStatus = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const slotId = parseInt(req.params.slotId as string);
    const { isActive } = req.body;

    if (typeof isActive !== 'boolean') {
      res.status(400).json({ error: 'isActive boolean is required' });
      return;
    }

    // Verify ownership
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('device_id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    // Update the database
    const { error } = await supabase
      .from('fingerprint_profiles')
      .update({ is_active: isActive })
      .eq('vehicle_id', vehicleId)
      .eq('slot_id', slotId);

    if (error) {
      res.status(500).json({ error: 'Failed to update fingerprint profile status' });
      return;
    }

    // Send command to ESP32
    publishCommand(vehicle.device_id, 'setDriverStatus', { driverId: slotId, isActive });
    
    res.status(200).json({ message: `Fingerprint ${isActive ? 'activated' : 'deactivated'} successfully` });
  } catch (err) {
    console.error('[Vehicle] Toggle fingerprint status error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /vehicles/:id/auth-bypass
export const setAuthBypass = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const { state } = req.body; // boolean

    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('device_id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    // state = true means bypassed (unlocked), so is_engine_locked = false.
    // state = false means normal (locked), so is_engine_locked = true.
    await supabase
      .from('vehicles')
      .update({ is_engine_locked: !state })
      .eq('id', vehicleId);

    publishCommand(vehicle.device_id, 'setAuthBypass', { state: !!state });
    
    res.status(200).json({ message: 'Auth bypass command sent to vehicle' });
  } catch (err) {
    console.error('[Vehicle] Set auth bypass error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /vehicles/register — Owner claims a device
export const registerVehicle = async (req: Request, res: Response): Promise<void> => {
  try {
    const { name, plateNumber, type } = req.body;
    const deviceId = req.body.deviceId?.toUpperCase();
    const ownerId = req.user.id;

    if (!deviceId || !name || !plateNumber) {
      res.status(400).json({ error: 'deviceId, name, and plateNumber are required' });
      return;
    }

    // Check if this device is already claimed by someone
    const { data: existing } = await supabase
      .from('vehicles')
      .select('id, owner_id')
      .eq('device_id', deviceId)
      .single();

    if (existing) {
      if (existing.owner_id === ownerId) {
        res.status(409).json({ error: 'You have already registered this device' });
      } else {
        res.status(409).json({ error: 'This device is already claimed by another user' });
      }
      return;
    }

    // Register the vehicle
    const { data, error } = await supabase
      .from('vehicles')
      .insert({
        device_id: deviceId,
        name: name,
        plate_number: plateNumber,
        type: type || 'Car',
        owner_id: ownerId,
        status: 'offline',
      })
      .select()
      .single();

    if (error) {
      console.error('[Vehicle] Register error:', error);
      res.status(500).json({ error: 'Failed to register vehicle' });
      return;
    }

    console.log(`[Vehicle] Device ${deviceId} claimed by user ${ownerId}`);
    res.status(201).json({ message: 'Vehicle registered successfully', vehicle: data });
  } catch (err) {
    console.error('[Vehicle] Register error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// GET /vehicles — List all vehicles for the authenticated user
export const getVehicles = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;

    const { data, error } = await supabase
      .from('vehicles')
      .select('*')
      .eq('owner_id', ownerId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Vehicle] Fetch error:', error);
      res.status(500).json({ error: 'Failed to fetch vehicles' });
      return;
    }

    res.status(200).json(data || []);
  } catch (err) {
    console.error('[Vehicle] Fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// GET /vehicles/:id — Get a single vehicle (only if owned by user)
export const getVehicleById = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;

    const { data, error } = await supabase
      .from('vehicles')
      .select('*')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (error || !data) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    res.status(200).json(data);
  } catch (err) {
    console.error('[Vehicle] Fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// DELETE /vehicles/:id — Remove a vehicle (unclaim the device)
export const deleteVehicle = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;

    // Verify ownership before deleting
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('id, device_id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found or you do not own it' });
      return;
    }

    const { error } = await supabase
      .from('vehicles')
      .delete()
      .eq('id', vehicleId);

    if (error) {
      console.error('[Vehicle] Delete error:', error);
      res.status(500).json({ error: 'Failed to delete vehicle' });
      return;
    }

    console.log(`[Vehicle] Device ${vehicle.device_id} unclaimed by user ${ownerId}`);
    res.status(200).json({ message: 'Vehicle removed successfully' });
  } catch (err) {
    console.error('[Vehicle] Delete error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// PUT /vehicles/:id — Update vehicle settings
export const updateVehicle = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const { name, plate_number, type, update_interval, connection_mode } = req.body;

    // Verify ownership
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found or you do not own it' });
      return;
    }

    const { data, error } = await supabase
      .from('vehicles')
      .update({
        name,
        plate_number,
        type,
        update_interval,
        connection_mode
      })
      .eq('id', vehicleId)
      .select()
      .single();

    if (error) {
      console.error('[Vehicle] Update error:', error);
      res.status(500).json({ error: 'Failed to update vehicle settings' });
      return;
    }

    res.status(200).json({ message: 'Vehicle settings updated', vehicle: data });
  } catch (err) {
    console.error('[Vehicle] Update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /vehicles/:id/drivers — Assign a driver to a vehicle by email
export const assignDriver = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;
    const { email } = req.body;

    if (!email) {
      res.status(400).json({ error: 'Driver email is required' });
      return;
    }

    // Verify the owner actually owns this vehicle
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found or you do not own it' });
      return;
    }

    // 1. Check if the user already exists in public.users
    let { data: existingUser } = await supabase
      .from('users')
      .select('id')
      .eq('email', email.toLowerCase())
      .single();

    let driverId = existingUser?.id;

    // 2. If user doesn't exist, create an account for them
    if (!driverId) {
      const defaultPassword = 'DriverPassword123!'; // We'll assume the driver can reset this later
      const { data: authData, error: authError } = await supabase.auth.signUp({
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
      await supabase.from('users').insert({
        id: driverId,
        email: email.toLowerCase(),
        full_name: 'Fleet Driver',
        role: 'driver'
      });
    }

    // 3. Link driver to the vehicle in vehicle_drivers table
    const { error: linkError } = await supabase
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
  } catch (err) {
    console.error('[Vehicle] Assign driver error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// GET /vehicles/:id/trips — Get history of trips for a vehicle
export const getTrips = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const vehicleId = req.params.id;

    // Verify ownership
    const { data: vehicle } = await supabase
      .from('vehicles')
      .select('id')
      .eq('id', vehicleId)
      .eq('owner_id', ownerId)
      .single();

    if (!vehicle) {
      res.status(404).json({ error: 'Vehicle not found' });
      return;
    }

    const { data, error } = await supabase
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
  } catch (err) {
    console.error('[Trip] Fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};
