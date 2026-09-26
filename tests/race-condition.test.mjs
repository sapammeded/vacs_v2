import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import crypto from "node:crypto";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");

const supabase = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const plate = "B7777RCE";
const eventCount = 100;
const deviceId = "RACE-TEST";
const marker = "RACE_TEST";
const eventIds = Array.from({ length: eventCount }, () => crypto.randomUUID());

const { data: location, error: locationError } = await supabase
  .from("locations").select("id").eq("code", "VACS-TEST").single();
assert.ifError(locationError);

const { data: gate, error: gateError } = await supabase
  .from("gates").select("id").eq("location_id", location.id).eq("code", "GATE-TEST").single();
assert.ifError(gateError);

const { data: operator, error: operatorError } = await supabase
  .from("profiles").select("id").eq("role", "admin").eq("active", true).limit(1).single();
assert.ifError(operatorError);

// Ensure this dedicated race-test plate is authorized.
const { error: authError } = await supabase.from("authorizations").upsert({
  location_id: location.id,
  plate_number: plate,
  valid_from: new Date(Date.now() - 86400000).toISOString().slice(0, 10),
  valid_until: new Date(Date.now() + 86400000).toISOString().slice(0, 10),
  start_time: "00:00:00",
  end_time: "23:59:00",
  allowed_weekdays: [1,2,3,4,5,6,7],
  allowed_gate_ids: [gate.id],
  allowed_directions: ["IN", "OUT"],
  active: true,
  notes: marker
}, { onConflict: "location_id,plate_number" });
assert.ifError(authError);

// A previous interrupted run must not leave the dedicated vehicle inside.
const { error: clearError } = await supabase
  .from("active_vehicle_state")
  .delete()
  .eq("location_id", location.id)
  .eq("plate_number", plate);
assert.ifError(clearError);

const started = Date.now();

const results = await Promise.all(
  eventIds.map((eventId, i) =>
    supabase.rpc("process_gate_event", {
      p_event_id: eventId,
      p_location_id: location.id,
      p_gate_id: gate.id,
      p_plate_number: plate,
      p_driver_name: `Race Test ${i + 1}`,
      p_direction: "IN",
      p_device_id: deviceId,
      p_device_time: new Date().toISOString(),
      p_operator_id: operator.id,
      p_notes: marker
    })
  )
);

const errors = results.filter(r => r.error);
assert.equal(errors.length, 0, JSON.stringify(errors, null, 2));

const rows = results.flatMap(r => r.data ?? []);
const authorized = rows.filter(r => r.result === "AUTHORIZED");
const duplicate = rows.filter(r => r.result === "DENIED" && r.reason === "DUPLICATE_IN");

assert.equal(rows.length, eventCount, "Every concurrent request must return one result");
assert.equal(authorized.length, 1, "Exactly one concurrent IN may be AUTHORIZED");
assert.equal(duplicate.length, eventCount - 1, "All other concurrent IN requests must be DUPLICATE_IN");

const { data: active, error: activeError } = await supabase
  .from("active_vehicle_state")
  .select("in_event_id,plate_number")
  .eq("location_id", location.id)
  .eq("plate_number", plate)
  .single();
assert.ifError(activeError);
assert.equal(active.in_event_id, authorized[0].event_id);

const { count, error: countError } = await supabase
  .from("gate_events")
  .select("event_id", { count: "exact", head: true })
  .eq("location_id", location.id)
  .eq("plate_number", plate)
  .eq("notes", marker);
assert.ifError(countError);
assert.equal(count, eventCount, "Exactly 100 race-test events should be persisted");

console.log(JSON.stringify({
  PASS: true,
  eventCount,
  authorized: authorized.length,
  duplicateIn: duplicate.length,
  activeInEventId: active.in_event_id,
  elapsedMs: Date.now() - started
}, null, 2));

// Leave the test vehicle outside after a successful run.
const { data: outData, error: outError } = await supabase.rpc("process_gate_event", {
  p_event_id: crypto.randomUUID(),
  p_location_id: location.id,
  p_gate_id: gate.id,
  p_plate_number: plate,
  p_driver_name: "Race Test Cleanup",
  p_direction: "OUT",
  p_device_id: deviceId,
  p_device_time: new Date().toISOString(),
  p_operator_id: operator.id,
  p_notes: marker
});
assert.ifError(outError);
assert.equal(outData?.[0]?.result, "AUTHORIZED", "Race-test cleanup OUT must succeed");
