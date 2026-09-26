-- VACS v2 — Migration 006
-- Isolated test seed. Uses deterministic codes so it can be rerun safely.
-- This is TEST DATA only; remove/replace before production rollout.

BEGIN;

INSERT INTO public.locations (name, code, active)
VALUES ('VACS Test Location', 'VACS-TEST', true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    active = true;

INSERT INTO public.gates (location_id, name, code, active)
SELECT l.id, 'Test Gate', 'GATE-TEST', true
FROM public.locations l
WHERE l.code = 'VACS-TEST'
ON CONFLICT (location_id, code) DO UPDATE
SET name = EXCLUDED.name,
    active = true;

INSERT INTO public.vehicles (
  location_id, plate_number, name, division, vehicle_type, model, color, notes, active
)
SELECT
  l.id,
  'B9999VCS',
  'VACS Test Vehicle',
  'TEST',
  'CAR',
  'TEST',
  'WHITE',
  'TEST DATA ONLY',
  true
FROM public.locations l
WHERE l.code = 'VACS-TEST'
ON CONFLICT (location_id, plate_number) DO UPDATE
SET active = true;

INSERT INTO public.authorizations (
  location_id,
  plate_number,
  valid_from,
  valid_until,
  start_time,
  end_time,
  allowed_weekdays,
  allowed_gate_ids,
  allowed_directions,
  active,
  notes
)
SELECT
  l.id,
  'B9999VCS',
  CURRENT_DATE - 1,
  CURRENT_DATE + 30,
  '00:00',
  '23:59',
  ARRAY[1,2,3,4,5,6,7],
  ARRAY[g.id],
  ARRAY['IN','OUT'],
  true,
  'VACS TEST AUTHORIZATION'
FROM public.locations l
JOIN public.gates g
  ON g.location_id = l.id
 AND g.code = 'GATE-TEST'
WHERE l.code = 'VACS-TEST'
  AND NOT EXISTS (
    SELECT 1
    FROM public.authorizations a
    WHERE a.location_id = l.id
      AND upper(regexp_replace(a.plate_number, '[^A-Z0-9]', '', 'g')) = 'B9999VCS'
      AND a.notes = 'VACS TEST AUTHORIZATION'
  );

COMMIT;
