-- Run this in the Supabase SQL Editor to fix the 42501 permission errors:

-- Temporarily disable RLS on backend-managed tables so the Node.js API can insert/update automatically
ALTER TABLE public.trips DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.zones DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts DISABLE ROW LEVEL SECURITY;
