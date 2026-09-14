-- ============================================================
-- PathFinder Migration 004
-- Add is_alarm_active column to vehicles table
-- ============================================================

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS is_alarm_active BOOLEAN DEFAULT false;
