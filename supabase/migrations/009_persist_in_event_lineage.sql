-- VACS v2 — Migration 009
-- Fix persisted lineage on AUTHORIZED IN events.
-- The previous function returned p_event_id as in_event_id,
-- but did not persist gate_events.in_event_id for IN rows.
-- Idempotent retries therefore returned NULL lineage.

BEGIN;

CREATE OR REPLACE FUNCTION public.process_gate_event(
  p_event_id uuid,
  p_location_id uuid,
  p_gate_id uuid,
  p_plate_number text,
  p_driver_name text DEFAULT '',
  p_direction text DEFAULT 'IN',
  p_device_id text DEFAULT '',
  p_device_time timestamptz DEFAULT now(),
  p_operator_id uuid DEFAULT NULL,
  p_notes text DEFAULT ''
)
RETURNS TABLE (
  event_id uuid,
  result text,
  reason text,
  in_event_id uuid,
  server_time timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plate text;
  v_direction text;
  v_now timestamptz := now();
  v_existing gate_events%ROWTYPE;
  v_active active_vehicle_state%ROWTYPE;
  v_auth authorizations%ROWTYPE;
  v_operator profiles%ROWTYPE;
  v_weekday int;
  v_has_active boolean := false;
  v_reason text;
BEGIN
  v_plate := upper(regexp_replace(trim(coalesce(p_plate_number, '')), '[^A-Z0-9]', '', 'g'));
  v_direction := upper(trim(coalesce(p_direction, '')));

  IF p_event_id IS NULL THEN RAISE EXCEPTION 'event_id is required'; END IF;
  IF v_plate = '' THEN RAISE EXCEPTION 'plate_number is required'; END IF;
  IF v_direction NOT IN ('IN','OUT') THEN RAISE EXCEPTION 'direction must be IN or OUT'; END IF;
  IF p_location_id IS NULL OR p_gate_id IS NULL OR p_operator_id IS NULL THEN
    RAISE EXCEPTION 'location_id, gate_id and operator_id are required';
  END IF;

  SELECT ge.* INTO v_existing
  FROM public.gate_events AS ge
  WHERE ge.event_id = p_event_id;

  IF FOUND THEN
    RETURN QUERY
    SELECT v_existing.event_id, v_existing.result, v_existing.reason,
           v_existing.in_event_id, v_existing.server_time;
    RETURN;
  END IF;

  SELECT pr.* INTO v_operator
  FROM public.profiles AS pr
  WHERE pr.id = p_operator_id AND pr.active = true;

  IF NOT FOUND THEN RAISE EXCEPTION 'operator is not active or does not exist'; END IF;

  PERFORM 1 FROM public.locations AS l
  WHERE l.id = p_location_id AND l.active = true;

  IF NOT FOUND THEN RAISE EXCEPTION 'location is not active or does not exist'; END IF;

  PERFORM 1 FROM public.gates AS g
  WHERE g.id = p_gate_id
    AND g.location_id = p_location_id
    AND g.active = true;

  IF NOT FOUND THEN RAISE EXCEPTION 'gate is not active or does not belong to location'; END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_location_id::text || ':' || v_plate, 0)
  );

  SELECT ge.* INTO v_existing
  FROM public.gate_events AS ge
  WHERE ge.event_id = p_event_id;

  IF FOUND THEN
    RETURN QUERY
    SELECT v_existing.event_id, v_existing.result, v_existing.reason,
           v_existing.in_event_id, v_existing.server_time;
    RETURN;
  END IF;

  v_has_active := EXISTS (
    SELECT 1 FROM public.active_vehicle_state AS avs
    WHERE avs.location_id = p_location_id
      AND avs.plate_number = v_plate
  );

  IF v_has_active THEN
    SELECT avs.* INTO v_active
    FROM public.active_vehicle_state AS avs
    WHERE avs.location_id = p_location_id
      AND avs.plate_number = v_plate
    FOR UPDATE;
  ELSE
    v_active := NULL;
  END IF;

  IF v_direction = 'IN' AND v_has_active THEN
    v_reason := 'DUPLICATE_IN';

    INSERT INTO public.gate_events (
      event_id, location_id, gate_id, plate_number, driver_name,
      direction, result, reason, operator_id, device_id,
      device_time, server_time, notes
    )
    VALUES (
      p_event_id, p_location_id, p_gate_id, v_plate,
      coalesce(p_driver_name,''), 'IN', 'DENIED', v_reason,
      p_operator_id, coalesce(p_device_id,''), p_device_time,
      v_now, coalesce(p_notes,'')
    );

    INSERT INTO public.audit_logs(event_id, actor_id, action, payload)
    VALUES (
      p_event_id, p_operator_id, 'GATE_IN_DENIED',
      jsonb_build_object('reason',v_reason,'plate_number',v_plate)
    );

    RETURN QUERY SELECT p_event_id,'DENIED'::text,v_reason,NULL::uuid,v_now;
    RETURN;
  END IF;

  IF v_direction = 'OUT' AND NOT v_has_active THEN
    v_reason := 'NO_ACTIVE_IN';

    INSERT INTO public.gate_events (
      event_id, location_id, gate_id, plate_number, driver_name,
      direction, result, reason, operator_id, device_id,
      device_time, server_time, notes
    )
    VALUES (
      p_event_id, p_location_id, p_gate_id, v_plate,
      coalesce(p_driver_name,''), 'OUT', 'DENIED', v_reason,
      p_operator_id, coalesce(p_device_id,''), p_device_time,
      v_now, coalesce(p_notes,'')
    );

    INSERT INTO public.audit_logs(event_id, actor_id, action, payload)
    VALUES (
      p_event_id, p_operator_id, 'GATE_OUT_DENIED',
      jsonb_build_object('reason',v_reason,'plate_number',v_plate)
    );

    RETURN QUERY SELECT p_event_id,'DENIED'::text,v_reason,NULL::uuid,v_now;
    RETURN;
  END IF;

  v_weekday := EXTRACT(ISODOW FROM v_now)::int;

  SELECT a.* INTO v_auth
  FROM public.authorizations AS a
  WHERE a.location_id = p_location_id
    AND a.active = true
    AND upper(regexp_replace(a.plate_number,'[^A-Z0-9]','','g')) = v_plate
    AND (a.valid_from IS NULL OR CURRENT_DATE >= a.valid_from)
    AND (a.valid_until IS NULL OR CURRENT_DATE <= a.valid_until)
    AND (a.allowed_weekdays IS NULL OR v_weekday = ANY(a.allowed_weekdays))
    AND (a.allowed_gate_ids IS NULL OR p_gate_id = ANY(a.allowed_gate_ids))
    AND (a.allowed_directions IS NULL OR v_direction = ANY(a.allowed_directions))
    AND (
      a.start_time IS NULL OR a.end_time IS NULL OR
      CASE
        WHEN a.start_time <= a.end_time
        THEN LOCALTIME BETWEEN a.start_time AND a.end_time
        ELSE LOCALTIME >= a.start_time OR LOCALTIME <= a.end_time
      END
    )
  ORDER BY a.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    v_reason := 'NOT_AUTHORIZED';

    INSERT INTO public.gate_events (
      event_id, location_id, gate_id, plate_number, driver_name,
      direction, result, reason, operator_id, device_id,
      device_time, server_time, notes
    )
    VALUES (
      p_event_id,p_location_id,p_gate_id,v_plate,coalesce(p_driver_name,''),
      v_direction,'DENIED',v_reason,p_operator_id,coalesce(p_device_id,''),
      p_device_time,v_now,coalesce(p_notes,'')
    );

    INSERT INTO public.audit_logs(event_id,actor_id,action,payload)
    VALUES (
      p_event_id,p_operator_id,
      CASE WHEN v_direction='IN' THEN 'GATE_IN_DENIED' ELSE 'GATE_OUT_DENIED' END,
      jsonb_build_object('reason',v_reason,'plate_number',v_plate)
    );

    RETURN QUERY SELECT p_event_id,'DENIED'::text,v_reason,NULL::uuid,v_now;
    RETURN;
  END IF;

  IF v_direction = 'IN' THEN
    -- IMPORTANT: persist in_event_id on the IN event itself.
    INSERT INTO public.gate_events (
      event_id, location_id, gate_id, plate_number, driver_name,
      direction, result, reason, operator_id, device_id,
      device_time, server_time, notes, in_event_id
    )
    VALUES (
      p_event_id,p_location_id,p_gate_id,v_plate,coalesce(p_driver_name,''),
      'IN','AUTHORIZED','AUTHORIZED',p_operator_id,coalesce(p_device_id,''),
      p_device_time,v_now,coalesce(p_notes,''),p_event_id
    );

    INSERT INTO public.active_vehicle_state (
      location_id,plate_number,in_event_id,in_gate_id,driver_name,entered_at
    )
    VALUES (
      p_location_id,v_plate,p_event_id,p_gate_id,
      coalesce(p_driver_name,''),v_now
    );

    INSERT INTO public.audit_logs(event_id,actor_id,action,payload)
    VALUES (
      p_event_id,p_operator_id,'GATE_IN_AUTHORIZED',
      jsonb_build_object('plate_number',v_plate,'gate_id',p_gate_id)
    );

    RETURN QUERY
    SELECT p_event_id,'AUTHORIZED'::text,'AUTHORIZED'::text,p_event_id,v_now;
    RETURN;
  END IF;

  INSERT INTO public.gate_events (
    event_id,location_id,gate_id,plate_number,driver_name,
    direction,result,reason,operator_id,device_id,
    device_time,server_time,notes,in_event_id
  )
  VALUES (
    p_event_id,p_location_id,p_gate_id,v_plate,coalesce(p_driver_name,''),
    'OUT','AUTHORIZED','AUTHORIZED',p_operator_id,coalesce(p_device_id,''),
    p_device_time,v_now,coalesce(p_notes,''),v_active.in_event_id
  );

  DELETE FROM public.active_vehicle_state
  WHERE location_id = p_location_id AND plate_number = v_plate;

  INSERT INTO public.audit_logs(event_id,actor_id,action,payload)
  VALUES (
    p_event_id,p_operator_id,'GATE_OUT_AUTHORIZED',
    jsonb_build_object(
      'plate_number',v_plate,
      'gate_id',p_gate_id,
      'in_event_id',v_active.in_event_id
    )
  );

  RETURN QUERY
  SELECT p_event_id,'AUTHORIZED'::text,'AUTHORIZED'::text,
         v_active.in_event_id,v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.process_gate_event(
  uuid,uuid,uuid,text,text,text,text,timestamptz,uuid,text
) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.process_gate_event(
  uuid,uuid,uuid,text,text,text,text,timestamptz,uuid,text
) TO service_role;

COMMIT;
