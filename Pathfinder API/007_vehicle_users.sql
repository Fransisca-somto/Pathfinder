-- ============================================================
-- PathFinder Migration 007
-- Add vehicle_users join table for multi-user device claiming
--
-- Replaces the single vehicles.owner_id column as the authority
-- for who has access to a vehicle. Multiple users can now claim
-- the same device ID and all receive full access.
--
-- vehicles.owner_id is preserved (NOT dropped) as an audit trail
-- of the original claimer and for compatibility with existing RLS
-- policies. It is no longer used for access control in the API.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.vehicle_users (
  vehicle_id  UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id)    ON DELETE CASCADE,
  -- role is reserved for a future ACL system (owner / viewer / mechanic).
  -- Every row is 'owner' for now — all claimants have identical permissions.
  role        TEXT NOT NULL DEFAULT 'owner',
  claimed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (vehicle_id, user_id)
);

-- Backfill: every existing owner_id row becomes the first vehicle_users entry.
-- ON CONFLICT DO NOTHING is safe to re-run if the migration is applied twice.
INSERT INTO public.vehicle_users (vehicle_id, user_id, role)
SELECT id, owner_id, 'owner'
FROM   public.vehicles
WHERE  owner_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- RLS: users can see and manage only their own links.
ALTER TABLE public.vehicle_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own vehicle links"
  ON public.vehicle_users FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own vehicle links"
  ON public.vehicle_users FOR ALL
  USING (auth.uid() = user_id);
