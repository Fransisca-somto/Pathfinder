import { Request, Response } from 'express';
import { supabase } from '../config/supabase';
import { refreshZoneCache } from '../services/zoneService';

// Helper to map DB record to Flutter model
const mapZoneToFlutter = (data: any) => ({
  id: data.id,
  name: data.name,
  type: data.type,
  shape: data.shape_type,
  radius: data.radius_meters,
  is_active: true, // Not stored in DB currently, default to true
  coordinates: {
    centerLatitude: data.center_latitude || 0.0,
    centerLongitude: data.center_longitude || 0.0,
    polygonPoints: data.polygon_points || []
  },
  owner_id: data.owner_id,
  created_at: data.created_at
});

// GET /zones — Fetch all zones for the authenticated user
export const getZones = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;

    const { data, error } = await supabase
      .from('zones')
      .select('*')
      .eq('owner_id', ownerId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Zone] Fetch error:', error);
      res.status(500).json({ error: 'Failed to fetch zones' });
      return;
    }

    const mappedData = (data || []).map(mapZoneToFlutter);
    res.status(200).json(mappedData);
  } catch (err) {
    console.error('[Zone] Fetch error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /zones — Create a new geofence zone
export const createZone = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const { name, type, shape, coordinates, radius } = req.body;

    if (!name || !coordinates) {
      res.status(400).json({ error: 'name and coordinates are required' });
      return;
    }

    const { data, error } = await supabase
      .from('zones')
      .insert({
        name,
        type: type || 'safe',
        shape_type: shape || 'circle',
        center_latitude: coordinates.centerLatitude || 0.0,
        center_longitude: coordinates.centerLongitude || 0.0,
        polygon_points: coordinates.polygonPoints || [],
        radius_meters: radius || 0,
        owner_id: ownerId
      })
      .select()
      .single();

    if (error) {
      console.error('[Zone] Create error:', error);
      res.status(500).json({ error: 'Failed to create zone' });
      return;
    }

    await refreshZoneCache();
    res.status(201).json(mapZoneToFlutter(data));
  } catch (err) {
    console.error('[Zone] Create error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// PUT /zones/:id — Update a zone
export const updateZone = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const zoneId = req.params.id;
    const { name, type, shape, coordinates, radius } = req.body;

    // Verify ownership
    const { data: existing } = await supabase
      .from('zones')
      .select('id')
      .eq('id', zoneId)
      .eq('owner_id', ownerId)
      .single();

    if (!existing) {
      res.status(404).json({ error: 'Zone not found' });
      return;
    }

    const updatePayload: any = {};
    if (name !== undefined) updatePayload.name = name;
    if (type !== undefined) updatePayload.type = type;
    if (shape !== undefined) updatePayload.shape_type = shape;
    if (radius !== undefined) updatePayload.radius_meters = radius;
    if (coordinates !== undefined) {
      if (coordinates.centerLatitude !== undefined) updatePayload.center_latitude = coordinates.centerLatitude;
      if (coordinates.centerLongitude !== undefined) updatePayload.center_longitude = coordinates.centerLongitude;
      if (coordinates.polygonPoints !== undefined) updatePayload.polygon_points = coordinates.polygonPoints;
    }

    const { data, error } = await supabase
      .from('zones')
      .update(updatePayload)
      .eq('id', zoneId)
      .select()
      .single();

    if (error) {
      console.error('[Zone] Update error:', error);
      res.status(500).json({ error: 'Failed to update zone' });
      return;
    }

    await refreshZoneCache();
    res.status(200).json(mapZoneToFlutter(data));
  } catch (err) {
    console.error('[Zone] Update error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// DELETE /zones/:id — Delete a zone
export const deleteZone = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const zoneId = req.params.id;

    // Verify ownership
    const { data: existing } = await supabase
      .from('zones')
      .select('id')
      .eq('id', zoneId)
      .eq('owner_id', ownerId)
      .single();

    if (!existing) {
      res.status(404).json({ error: 'Zone not found' });
      return;
    }

    const { error } = await supabase
      .from('zones')
      .delete()
      .eq('id', zoneId);

    if (error) {
      console.error('[Zone] Delete error:', error);
      res.status(500).json({ error: 'Failed to delete zone' });
      return;
    }

    await refreshZoneCache();
    res.status(200).json({ message: 'Zone deleted successfully' });
  } catch (err) {
    console.error('[Zone] Delete error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// GET /zones/:id/vehicles — Get assigned vehicles
export const getAssignedVehicles = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const zoneId = req.params.id;

    // Verify ownership
    const { data: existing } = await supabase.from('zones').select('id').eq('id', zoneId).eq('owner_id', ownerId).single();
    if (!existing) {
      res.status(404).json({ error: 'Zone not found' });
      return;
    }

    const { data, error } = await supabase.from('zone_vehicles').select('vehicle_id').eq('zone_id', zoneId);
    if (error) throw error;

    res.status(200).json((data || []).map(row => row.vehicle_id));
  } catch (err) {
    console.error('[Zone] Get assignments error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// POST /zones/:id/vehicles — Assign vehicles to zone
export const assignVehiclesToZone = async (req: Request, res: Response): Promise<void> => {
  try {
    const ownerId = req.user.id;
    const zoneId = req.params.id;
    const { vehicleIds } = req.body; // Array of vehicle IDs

    if (!Array.isArray(vehicleIds)) {
      res.status(400).json({ error: 'vehicleIds must be an array' });
      return;
    }

    // Verify ownership
    const { data: existing } = await supabase.from('zones').select('id').eq('id', zoneId).eq('owner_id', ownerId).single();
    if (!existing) {
      res.status(404).json({ error: 'Zone not found' });
      return;
    }

    // Delete existing assignments for this zone
    await supabase.from('zone_vehicles').delete().eq('zone_id', zoneId);

    // Insert new assignments
    if (vehicleIds.length > 0) {
      const inserts = vehicleIds.map(vid => ({ zone_id: zoneId, vehicle_id: vid }));
      const { error } = await supabase.from('zone_vehicles').insert(inserts);
      if (error) throw error;
    }

    await refreshZoneCache();
    res.status(200).json({ message: 'Vehicles assigned successfully' });
  } catch (err) {
    console.error('[Zone] Assign error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
};
