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
const marker = "IN_OUT_IN_TEST_V2";
const eventId = () => crypto.randomUUID();

const { data: location, error: locationError } = await supabase
  .from("locations").select("id").eq("code", "VACS-TEST").single();
assert.ifError(locationError);

const { data: gate, error: gateError } = await supabase
  .from("gates").select("id").eq("location_id", location.id).eq("code", "GATE-TEST").single();
assert.ifError(gateError);

const { data: operator, error: operatorError } = await supabase
  .from("profiles").select("id").eq("role", "admin").eq("active", true).limit(1).single();
assert.ifError(operatorError);

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

await supabase.from("active_vehicle_state")
  .delete()
  .eq("location_id", location.id)
  .eq("plate_number", plate);

const firstInId = eventId();
const { data: firstIn, error: firstInError } = await supabase.rpc("process_gate_event", {
  p_event_id: firstInId,
  p_location_id: location.id,
  p_gate_id: gate.id,
  p_plate_number: plate,
  p_driver_name: "IN-OUT-IN TEST",
  p_direction: "IN",
  p_device_id: "IN-OUT-IN-TEST",
  p_device_time: new Date().toISOString(),
  p_operator_id: operator.id,
  p_notes: marker
});
assert.ifError(firstInError);
assert.equal(firstIn?.[0]?.result, "AUTHORIZED");
assert.equal(firstIn?.[0]?.in_event_id, firstInId);

const outId = eventId();
const { data: out, error: outError } = await supabase.rpc("process_gate_event", {
  p_event_id: outId,
  p_location_id: location.id,
  p_gate_id: gate.id,
  p_plate_number: plate,
  p_driver_name: "IN-OUT-IN TEST",
  p_direction: "OUT",
  p_device_id: "IN-OUT-IN-TEST",
  p_device_time: new Date().toISOString(),
  p_operator_id: operator.id,
  p_notes: marker
});
assert.ifError(outError);
assert.equal(out?.[0]?.result, "AUTHORIZED");
assert.equal(out?.[0]?.in_event_id, firstInId);

const { data: afterOut, error: afterOutError } = await supabase
  .from("active_vehicle_state").select("in_event_id")
  .eq("location_id", location.id).eq("plate_number", plate).maybeSingle();
assert.ifError(afterOutError);
assert.equal(afterOut, null, "Vehicle must be absent from active state after OUT");

const secondInId = eventId();
const { data: secondIn, error: secondInError } = await supabase.rpc("process_gate_event", {
  p_event_id: secondInId,
  p_location_id: location.id,
  p_gate_id: gate.id,
  p_plate_number: plate,
  p_driver_name: "IN-OUT-IN TEST",
  p_direction: "IN",
  p_device_id: "IN-OUT-IN-TEST",
  p_device_time: new Date().toISOString(),
  p_operator_id: operator.id,
  p_notes: marker
});
assert.ifError(secondInError);
assert.equal(secondIn?.[0]?.result, "AUTHORIZED");
assert.equal(secondIn?.[0]?.in_event_id, secondInId);

const { data: active, error: activeError } = await supabase
  .from("active_vehicle_state").select("in_event_id")
  .eq("location_id", location.id).eq("plate_number", plate).single();
assert.ifError(activeError);
assert.equal(active.in_event_id, secondInId);

console.log(JSON.stringify({
  PASS: true,
  first_in: firstInId,
  out: outId,
  out_linked_to: out?.[0]?.in_event_id,
  second_in: secondInId,
  active_in_event_id: active.in_event_id
}, null, 2));

const cleanupId = eventId();
const { data: cleanup, error: cleanupError } = await supabase.rpc("process_gate_event", {
  p_event_id: cleanupId,
  p_location_id: location.id,
  p_gate_id: gate.id,
  p_plate_number: plate,
  p_driver_name: "IN-OUT-IN TEST CLEANUP",
  p_direction: "OUT",
  p_device_id: "IN-OUT-IN-TEST",
  p_device_time: new Date().toISOString(),
  p_operator_id: operator.id,
  p_notes: marker
});
assert.ifError(cleanupError);
assert.equal(cleanup?.[0]?.result, "AUTHORIZED");
