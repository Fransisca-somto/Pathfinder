-- ============================================================
-- PathFinder Migration 003
-- Add missing route_path column to trips table
-- ============================================================

ALTER TABLE public.trips
  ADD COLUMN IF NOT EXISTS route_path JSONB DEFAULT '[]'::jsonb;
