-- ============================================================
-- PathFinder Firmware Migration 001
-- ============================================================
-- Run this in your Supabase SQL Editor BEFORE deploying the API
-- or flashing the new firmware on devices.
--
-- All battery/telemetry data before this migration used
-- fabricated voltage values. Do not chart pre-migration battery
-- data alongside post-migration data.
--
-- Every statement is idempotent (IF NOT EXISTS / safe to re-run).
-- ============================================================

-- ============================================================
-- 1. VEHICLES TABLE — New telemetry columns
-- ============================================================

-- Battery voltage (real value from firmware, was previously wrong)
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS battery_voltage DOUBLE PRECISION;

-- Charging flag (true when alternator is running, voltage >= 13.2V)
-- When true, battery percentage is meaningless — display "Charging"
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS charging BOOLEAN DEFAULT false;

-- Power disconnected flag (true below 5V — strongest theft signal)
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS power_cut BOOLEAN DEFAULT false;

-- Current driver fingerprint slot (1-127, or -1 when unattributed)
-- Persists across device reboots
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS current_driver_id INTEGER DEFAULT -1;

-- Emergency SMS contact (international format: +234...)
-- Server-side authoritative copy — device does not echo it back
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS emergency_contact TEXT;

-- Engine temperature column (may already exist if created manually)
-- Making sure it exists for completeness. DOUBLE PRECISION is
-- nullable by default in PostgreSQL, which is what we need for
-- the new firmware's null-on-sensor-fault behavior.
ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS engine_temperature DOUBLE PRECISION;

-- ============================================================
-- 2. ALERTS TABLE — New fields for driver attribution + dedup
-- ============================================================

-- Driver fingerprint slot associated with this alert (1-127, or NULL)
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS driver_id INTEGER;

-- Device uptime in seconds since boot (resets on reboot)
-- Used for deduplication key, NOT as a timestamp
ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS uptime INTEGER;

-- ============================================================
-- 3. ALERTS TABLE — Switch type from ENUM to TEXT
-- ============================================================
-- The API already inserts raw strings. The old ENUM only had:
--   speed, zoneExit, zoneEnter, maintenance, system, panic
-- The new firmware adds 7+ types (authDenied, enrollProgress,
-- enrollSuccess, enrollFailed, sensorFault, danger, call, etc.)
-- TEXT is simpler, future-proof, and avoids ALTER TYPE migrations.

ALTER TABLE public.alerts
  ALTER COLUMN type SET DEFAULT 'system';

ALTER TABLE public.alerts
  ALTER COLUMN type TYPE TEXT;

-- ============================================================
-- 4. ALERTS TABLE — Deduplication index
-- ============================================================
-- The firmware now queues alerts on SD card and retries after
-- reconnection (3 every 2 seconds). A failed queue rewrite
-- causes deliberate re-sends. The API deduplicates on:
--   (vehicle_id, type, message, uptime)
-- This index supports that lookup.

CREATE INDEX IF NOT EXISTS idx_alerts_dedup
  ON public.alerts(vehicle_id, type, message, created_at);

-- ============================================================
-- 5. FINGERPRINT_PROFILES TABLE — Track enrollment timestamp
-- ============================================================

ALTER TABLE public.fingerprint_profiles
  ADD COLUMN IF NOT EXISTS enrolled_at TIMESTAMPTZ;
