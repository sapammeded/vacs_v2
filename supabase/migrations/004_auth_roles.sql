-- VACS v2 — Migration 004
-- Auth profile bootstrap and operator linkage.
-- Role is server-managed; new users always start as SECURITY.

BEGIN;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (
    id,
    role,
    display_name,
    phone,
    active
  )
  VALUES (
    NEW.id,
    'security',
    COALESCE(NEW.raw_user_meta_data ->> 'display_name', ''),
    NEW.phone,
    true
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Every gate event operator must correspond to a real VACS profile.
ALTER TABLE public.gate_events
  DROP CONSTRAINT IF EXISTS fk_gate_events_operator;

ALTER TABLE public.gate_events
  ADD CONSTRAINT fk_gate_events_operator
  FOREIGN KEY (operator_id)
  REFERENCES public.profiles(id);

COMMENT ON FUNCTION public.handle_new_user() IS
  'Creates a VACS profile for every Supabase Auth user. Role always starts as security and is not taken from user metadata.';

COMMIT;
