-- VACS v2 — Runtime grants for trusted Apps Script/Supabase service backend.
BEGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.vehicles TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.authorizations TO service_role;
GRANT SELECT, INSERT ON TABLE public.gate_events TO service_role;
GRANT SELECT, INSERT ON TABLE public.audit_logs TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.alerts TO service_role;
GRANT SELECT ON TABLE public.locations TO service_role;
GRANT SELECT ON TABLE public.gates TO service_role;
GRANT SELECT ON TABLE public.profiles TO service_role;
GRANT SELECT, INSERT, DELETE, UPDATE ON TABLE public.active_vehicle_state TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.audit_logs_id_seq TO service_role;
COMMIT;