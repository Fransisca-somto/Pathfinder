-- ============================================================
-- PathFinder Migration 009
-- Drop battery fields from vehicles table
--
-- The firmware no longer reports battery voltage, percentage,
-- or charging status. Power is now reported solely as a boolean
-- power_cut flag.
-- ============================================================

ALTER TABLE public.vehicles
  DROP COLUMN IF EXISTS battery,
  DROP COLUMN IF EXISTS battery_voltage,
  DROP COLUMN IF EXISTS charging;

-- Ensure power_cut column exists (it might have been added ad-hoc,
-- but good to make it explicit).
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS power_cut BOOLEAN DEFAULT false;

-- Notify postgrest to reload the schema cache
NOTIFY pgrst, 'reload schema';
