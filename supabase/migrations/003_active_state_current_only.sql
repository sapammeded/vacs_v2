-- VACS v2 — Migration 003
-- active_vehicle_state is CURRENT STATE only.
-- Historical IN/OUT lineage remains in gate_events.

BEGIN;

-- New project foundation is empty at this stage. Remove any legacy OUT-state rows.
DELETE FROM public.active_vehicle_state
WHERE status <> 'INSIDE';

ALTER TABLE public.active_vehicle_state
  DROP COLUMN IF EXISTS out_event_id,
  DROP COLUMN IF EXISTS out_gate_id,
  DROP COLUMN IF EXISTS exited_at,
  DROP COLUMN IF EXISTS status;

-- The primary key already guarantees one active vehicle per location.
ALTER TABLE public.active_vehicle_state
  DROP CONSTRAINT IF EXISTS active_vehicle_state_pkey;

ALTER TABLE public.active_vehicle_state
  ADD CONSTRAINT active_vehicle_state_pkey
  PRIMARY KEY (location_id, plate_number);

-- Remove the old partial index if it exists; it is redundant now.
DROP INDEX IF EXISTS public.uq_active_inside;

COMMENT ON TABLE public.active_vehicle_state IS
  'Current vehicle state only. A row exists only while the vehicle is INSIDE. Authorized OUT deletes the row after recording the OUT event in gate_events.';

COMMIT;
