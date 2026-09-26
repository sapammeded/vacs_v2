-- VACS v2 — roles + event lineage
-- Safe follow-up migration. Does not drop production tables.

CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'security'
        CHECK (role IN ('admin','security','viewer')),
    display_name TEXT,
    phone TEXT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- No public/anon client policy yet.
-- Backend uses the protected server-side database connection.

ALTER TABLE gate_events
    ADD COLUMN IF NOT EXISTS in_event_id UUID
    REFERENCES gate_events(event_id);

CREATE INDEX IF NOT EXISTS idx_gate_events_in_event
    ON gate_events(in_event_id);

-- active_vehicle_state is intentionally a CURRENT-STATE table.
-- Historical IN -> OUT lineage lives permanently in gate_events.in_event_id.
-- The backend will DELETE the active-state row when an authorized OUT occurs.
-- This allows the same vehicle to perform IN -> OUT -> IN repeatedly.

ALTER TABLE active_vehicle_state
    DROP CONSTRAINT IF EXISTS active_vehicle_state_pkey;

ALTER TABLE active_vehicle_state
    ADD CONSTRAINT active_vehicle_state_pkey
    PRIMARY KEY(location_id, plate_number);

DROP INDEX IF EXISTS uq_active_inside;

CREATE UNIQUE INDEX IF NOT EXISTS uq_active_inside
    ON active_vehicle_state(location_id, plate_number);

COMMENT ON COLUMN gate_events.in_event_id IS
'For OUT events, points to the exact authorized IN event that opened the current visit. NULL for IN events.';

COMMENT ON TABLE active_vehicle_state IS
'Current-state projection only. One row means the vehicle is currently inside. Historical lineage is stored in gate_events.';
