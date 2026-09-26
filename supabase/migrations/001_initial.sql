create extension if not exists pgcrypto;

create table if not exists locations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists gates (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references locations(id) on delete cascade,
  name text not null,
  code text not null,
  active boolean not null default true,
  unique(location_id, code)
);

create table if not exists vehicles (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references locations(id) on delete cascade,
  plate_number text not null,
  name text,
  division text,
  vehicle_type text,
  model text,
  color text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(location_id, plate_number)
);

create table if not exists authorizations (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references locations(id) on delete cascade,
  plate_number text not null,
  valid_from date,
  valid_until date,
  start_time time,
  end_time time,
  allowed_weekdays int[],
  allowed_gate_ids uuid[],
  allowed_directions text[],
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists gate_events (
  event_id uuid primary key,
  location_id uuid not null references locations(id),
  gate_id uuid not null references gates(id),
  plate_number text not null,
  driver_name text not null default '',
  direction text not null check(direction in ('IN','OUT')),
  result text not null check(result in ('AUTHORIZED','DENIED')),
  reason text not null,
  operator_id uuid not null,
  device_id text not null,
  device_time timestamptz not null,
  server_time timestamptz not null default now(),
  notes text not null default ''
);

create table if not exists active_vehicle_state (
  location_id uuid not null references locations(id) on delete cascade,
  plate_number text not null,
  in_event_id uuid not null references gate_events(event_id),
  in_gate_id uuid not null references gates(id),
  driver_name text not null default '',
  entered_at timestamptz not null,
  out_event_id uuid references gate_events(event_id),
  out_gate_id uuid references gates(id),
  exited_at timestamptz,
  status text not null default 'INSIDE' check(status in ('INSIDE','OUT')),
  primary key(location_id, plate_number)
);

create table if not exists audit_logs (
  id bigserial primary key,
  event_id uuid references gate_events(event_id),
  actor_id uuid,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists alerts (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references locations(id),
  plate_number text,
  type text not null,
  severity text not null default 'INFO',
  message text not null,
  acknowledged_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_gate_events_plate_time
  on gate_events(location_id, plate_number, server_time desc);
create index if not exists idx_gate_events_time
  on gate_events(location_id, server_time desc);
create index if not exists idx_gate_events_result
  on gate_events(location_id, result, server_time desc);
create index if not exists idx_active_inside
  on active_vehicle_state(location_id, status, entered_at desc);
create index if not exists idx_audit_event
  on audit_logs(event_id);

create unique index if not exists uq_active_inside
  on active_vehicle_state(location_id, plate_number)
  where status='INSIDE';