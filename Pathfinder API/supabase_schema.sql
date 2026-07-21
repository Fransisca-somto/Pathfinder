-- PathFinder Supabase Database Schema

-- 1. Create custom ENUM types (Optional but recommended for strictness)
CREATE TYPE user_role AS ENUM ('owner', 'manager', 'driver');
CREATE TYPE vehicle_status AS ENUM ('moving', 'parked', 'offline', 'alarm');
CREATE TYPE alert_type AS ENUM ('speed', 'zoneExit', 'zoneEnter', 'maintenance', 'system', 'panic');
CREATE TYPE zone_type AS ENUM ('safe', 'restricted', 'speed');
CREATE TYPE shape_type AS ENUM ('circle', 'polygon');

-- 2. Create Users Table (extends auth.users)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE,
  full_name TEXT NOT NULL,
  phone TEXT,
  role user_role DEFAULT 'owner',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create Vehicles Table
CREATE TABLE public.vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  plate_number TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'Car',
  current_latitude DOUBLE PRECISION DEFAULT 0.0,
  current_longitude DOUBLE PRECISION DEFAULT 0.0,
  current_speed DOUBLE PRECISION DEFAULT 0.0,
  status vehicle_status DEFAULT 'offline',
  total_mileage DOUBLE PRECISION DEFAULT 0.0,
  last_known_location TEXT DEFAULT 'Unknown',
  is_engine_locked BOOLEAN DEFAULT false,
  update_interval TEXT DEFAULT '5s',
  device_id TEXT UNIQUE NOT NULL,
  connection_mode TEXT DEFAULT 'GPRS',
  gps_signal_strength INTEGER DEFAULT 4,
  owner_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Create Vehicle-Drivers Join Table (Many-to-Many)
CREATE TABLE public.vehicle_drivers (
  vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE CASCADE,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (vehicle_id, user_id)
);

-- 5. Create Zones Table (Geofencing)
CREATE TABLE public.zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type zone_type DEFAULT 'safe',
  shape_type shape_type DEFAULT 'circle',
  center_latitude DOUBLE PRECISION DEFAULT 0.0,
  center_longitude DOUBLE PRECISION DEFAULT 0.0,
  radius_meters DOUBLE PRECISION DEFAULT 0.0,
  polygon_points JSONB DEFAULT '[]'::jsonb,
  owner_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Create Zone-Vehicles Join Table (Assigning vehicles to specific zones)
CREATE TABLE public.zone_vehicles (
  zone_id UUID REFERENCES public.zones(id) ON DELETE CASCADE,
  vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE CASCADE,
  PRIMARY KEY (zone_id, vehicle_id)
);

-- 7. Create Alerts Table
CREATE TABLE public.alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type alert_type DEFAULT 'system',
  vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  requires_action BOOLEAN DEFAULT false,
  action_type TEXT DEFAULT '',
  owner_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Add a trigger to automatically create a profile in `public.users` when a user signs up via Supabase Auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, full_name, phone, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'phone',
    COALESCE((new.raw_user_meta_data->>'role')::user_role, 'owner'::user_role)
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Enable Row Level Security (RLS)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zone_vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;

-- Create basic RLS policies (Users can read/write their own data)
CREATE POLICY "Users can view own profile" ON public.users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.users FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Owners can view own vehicles" ON public.vehicles FOR SELECT USING (auth.uid() = owner_id);
CREATE POLICY "Owners can manage own vehicles" ON public.vehicles FOR ALL USING (auth.uid() = owner_id);

CREATE POLICY "Owners can view own alerts" ON public.alerts FOR SELECT USING (auth.uid() = owner_id);
CREATE POLICY "Owners can manage own alerts" ON public.alerts FOR ALL USING (auth.uid() = owner_id);

CREATE POLICY "Owners can view own zones" ON public.zones FOR SELECT USING (auth.uid() = owner_id);
CREATE POLICY "Owners can manage own zones" ON public.zones FOR ALL USING (auth.uid() = owner_id);

INSERT INTO public.users (id, full_name, phone, role)
SELECT id, raw_user_meta_data->>'full_name', raw_user_meta_data->>'phone', 'owner'
FROM auth.users
WHERE id NOT IN (SELECT id FROM public.users);
