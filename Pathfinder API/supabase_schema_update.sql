-- Run this in your Supabase SQL Editor to add Trip History capabilities:

CREATE TABLE public.trips (
  id uuid NOT NULL DEFAULT extensions.uuid_generate_v4(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  start_time timestamp with time zone NOT NULL,
  end_time timestamp with time zone NULL,
  start_lat double precision NOT NULL,
  start_lng double precision NOT NULL,
  end_lat double precision NULL,
  end_lng double precision NULL,
  start_address text NULL,
  end_address text NULL,
  distance_km double precision NULL,
  duration_mins integer NULL,
  CONSTRAINT trips_pkey PRIMARY KEY (id)
);

-- Index for fast lookup by vehicle
CREATE INDEX idx_trips_vehicle_id ON public.trips(vehicle_id);
