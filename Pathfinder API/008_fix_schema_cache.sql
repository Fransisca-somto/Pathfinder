-- ============================================================
-- PathFinder Migration 008
-- Fix public.users email column and schema cache
--
-- Resolves PGRST204: "Could not find the 'email' column of 
-- 'users' in the schema cache"
-- ============================================================

-- 1. Ensure the email column actually exists (in case the table
-- was created without it previously).
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS email TEXT UNIQUE;

-- 2. Force Supabase/PostgREST to reload its schema cache.
-- This tells the API to re-read the database schema so it sees
-- the email column and stops throwing PGRST204 errors.
NOTIFY pgrst, 'reload schema';
