import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import crypto from "node:crypto";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");

const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
const plate = "B7777RCE";
const eventCount = 100;
const marker = "RACE_TEST_V2";

const { data: location, error: le } = await supabase.from("locations").select("id").eq("code", "VACS-TEST").single();
assert.ifError(le);
const { data: gate, error: ge } = await supabase.from("gates").select("id").eq("location_id", location.id).eq("code", "GATE-TEST").single();
assert.ifError(ge);
const { data: operator, error: oe } = await supabase.from("profiles").select("id").eq("role", "admin").eq("active", true).limit(1).single();
assert.ifError(oe);

const { data: existingAuth, error: ae } = await supabase.from("authorizations")
  .select("id").eq("location_id", location.id).eq("plate_number", plate).eq("notes", marker).limit(1);
assert.ifError(ae);

if (!existingAuth.length) {
  const { error } = await supabase.from("authorizations").insert({
    location_id: location.id, plate_number: plate,
    valid_from: new Date(Date.now() - 86400000).toISOString().slice(0,10),
    valid_until: new Date(Date.now() + 86400000).toISOString().slice(0,10),
    start_time: "00:00:00", end_time: "23:59:00",
    allowed_weekdays: [1,2,3,4,5,6,7], allowed_gate_ids: [gate.id],
    allowed_directions: ["IN","OUT"], active: true, notes: marker
  });
  assert.ifError(error);
}

const { error: clear } = await supabase.from("active_vehicle_state")
  .delete().eq("location_id", location.id).eq("plate_number", plate);
assert.ifError(clear);

const eventIds = Array.from({length:eventCount}, () => crypto.randomUUID());
const start = Date.now();

const responses = await Promise.all(eventIds.map((eventId, i) =>
  supabase.rpc("process_gate_event", {
    p_event_id:eventId, p_location_id:location.id, p_gate_id:gate.id,
    p_plate_number:plate, p_driver_name:`Race Test ${i+1}`,
    p_direction:"IN", p_device_id:"RACE-TEST", p_device_time:new Date().toISOString(),
    p_operator_id:operator.id, p_notes:marker
  })
));

const errors = responses.filter(x => x.error);
assert.equal(errors.length, 0, JSON.stringify(errors, null, 2));
const rows = responses.flatMap(x => x.data ?? []);
const authorized = rows.filter(x => x.result === "AUTHORIZED");
const duplicate = rows.filter(x => x.result === "DENIED" && x.reason === "DUPLICATE_IN");

assert.equal(rows.length, eventCount);
assert.equal(authorized.length, 1, "Exactly one IN must be AUTHORIZED");
assert.equal(duplicate.length, eventCount - 1, "All remaining INs must be DUPLICATE_IN");

const { data: active, error: se } = await supabase.from("active_vehicle_state")
  .select("in_event_id").eq("location_id", location.id).eq("plate_number", plate).single();
assert.ifError(se);
assert.equal(active.in_event_id, authorized[0].event_id);

console.log(JSON.stringify({
  PASS:true, requests:eventCount, authorized:authorized.length,
  duplicate_in:duplicate.length, active_in_event_id:active.in_event_id,
  elapsed_ms:Date.now()-start
}, null, 2));

const { data: cleanup, error: ce } = await supabase.rpc("process_gate_event", {
  p_event_id:crypto.randomUUID(), p_location_id:location.id, p_gate_id:gate.id,
  p_plate_number:plate, p_driver_name:"Race Test Cleanup", p_direction:"OUT",
  p_device_id:"RACE-TEST", p_device_time:new Date().toISOString(),
  p_operator_id:operator.id, p_notes:marker
});
assert.ifError(ce);
assert.equal(cleanup?.[0]?.result, "AUTHORIZED");
