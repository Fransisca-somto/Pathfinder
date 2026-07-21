import { supabase } from '../config/supabase';

// Helper: Haversine distance in kilometers
const calculateDistanceKm = (lat1: number, lon1: number, lat2: number, lon2: number) => {
  const R = 6371; // Radius of the earth in km
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) *
      Math.cos(lat2 * (Math.PI / 180)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
};

// Helper: Reverse Geocoding with Nominatim OSM
const getAddressFromCoords = async (lat: number, lng: number): Promise<string> => {
  try {
    const url = `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&email=admin@uniziktracker.com`;
    
    // Nominatim strictly requires a unique User-Agent
    const response = await fetch(url, {
      headers: {
        'User-Agent': 'UnizikTrackerApp/1.0'
      }
    });

    if (!response.ok) {
      console.warn(`[TripService] Nominatim API failed with status ${response.status}`);
      return `${lat.toFixed(4)}, ${lng.toFixed(4)}`; // Fallback
    }

    const data: any = await response.json();
    
    if (data && data.address) {
      // Build a short address like "Ikeja City Mall, Lagos"
      const locationName = data.address.retail || data.address.road || data.address.suburb || data.address.neighbourhood || data.address.city || 'Unknown Road';
      const city = data.address.city || data.address.state || data.address.country || 'Unknown City';
      return `${locationName}, ${city}`;
    }

    return data?.display_name?.split(',').slice(0, 2).join(',') || `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
  } catch (err) {
    console.error('[TripService] Reverse Geocoding Error:', err);
    return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
  }
};

export const startTrip = async (vehicleId: string, lat: number, lng: number) => {
  try {
    console.log(`[TripService] Starting new trip for vehicle ${vehicleId}`);

    // Fetch address asynchronously
    const startAddress = await getAddressFromCoords(lat, lng);

    const { error } = await supabase.from('trips').insert({
      vehicle_id: vehicleId,
      start_time: new Date().toISOString(),
      start_lat: lat,
      start_lng: lng,
      start_address: startAddress
    });

    if (error) {
      console.error('[TripService] Failed to insert new trip:', error);
    }
  } catch (err) {
    console.error('[TripService] startTrip error:', err);
  }
};

export const endTrip = async (vehicleId: string, lat: number, lng: number) => {
  try {
    // 1. Find the latest open trip for this vehicle
    const { data: openTrip, error: fetchError } = await supabase
      .from('trips')
      .select('*')
      .eq('vehicle_id', vehicleId)
      .is('end_time', null)
      .order('start_time', { ascending: false })
      .limit(1)
      .single();

    if (fetchError || !openTrip) {
      console.log(`[TripService] No open trip found to end for vehicle ${vehicleId}`);
      return;
    }

    console.log(`[TripService] Ending trip ${openTrip.id} for vehicle ${vehicleId}`);

    // 2. Calculate duration
    const endTime = new Date();
    const startTime = new Date(openTrip.start_time);
    const durationMins = Math.round((endTime.getTime() - startTime.getTime()) / 60000);

    // 3. Calculate distance
    const distanceKm = calculateDistanceKm(openTrip.start_lat, openTrip.start_lng, lat, lng);

    // 4. Reverse Geocode End Location
    const endAddress = await getAddressFromCoords(lat, lng);

    // 5. Update the trip
    const { error: updateError } = await supabase
      .from('trips')
      .update({
        end_time: endTime.toISOString(),
        end_lat: lat,
        end_lng: lng,
        end_address: endAddress,
        distance_km: parseFloat(distanceKm.toFixed(2)),
        duration_mins: durationMins
      })
      .eq('id', openTrip.id);

    if (updateError) {
      console.error('[TripService] Failed to update ended trip:', updateError);
    } else {
      console.log(`[TripService] Trip ${openTrip.id} ended successfully.`);
    }

  } catch (err) {
    console.error('[TripService] endTrip error:', err);
  }
};
