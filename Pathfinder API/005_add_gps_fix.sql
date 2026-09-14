-- ============================================================
-- PathFinder Migration 005
-- Add gps_fix and fix_age_s columns to vehicles table
-- ============================================================

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS gps_fix BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS fix_age_s INTEGER DEFAULT 0;
