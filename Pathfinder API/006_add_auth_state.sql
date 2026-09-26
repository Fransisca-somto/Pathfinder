-- ============================================================
-- PathFinder Migration 006
-- Add auth_state column to vehicles table
--
-- auth_state mirrors the device's finite-state machine:
--   "armed"      — waiting for a fingerprint
--   "authorised" — relays live, 60-second start window open
--   "running"    — engine detected (acc line high)
--   "grace"      — engine stopped, 120-second restart window open
--
-- Written on every telemetry packet so the row always reflects
-- the device's actual state, not just discrete alert events.
-- ============================================================

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS auth_state TEXT DEFAULT 'armed';
