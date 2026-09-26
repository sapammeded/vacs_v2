import assert from "node:assert/strict";
import { createClient } from "@supabase/supabase-js";
import crypto from "node:crypto";

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required");
const supabase = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
const plate = "B7777RCE";
const eventId = () => crypto.randomUUID();
const now = new Date();
const yesterday = new Date(now.getTime() - 86400000);

const { data: location, error: le } = await supabase.from("locations").select("id").eq("code", "VACS-TEST").single();
assert.ifError(le);
const { data: gate, error: ge } = await supabase.from("gates").select("id").eq("location_id", location.id).eq("code", "GATE-TEST").single();
assert.ifError(ge);
const { data: operator, error: oe } = await supabase.from("profiles").select("id").eq("role", "admin").eq("active", true).limit(1).single();
assert.ifError(oe);
const { data: auth, error: ae } = await supabase.from("authorizations").select("id").eq("location_id", location.id).eq("plate_number", plate).eq("active", true).single();
assert.ifError(ae);
assert.ok(auth?.id);
await supabase.from("active_vehicle_state").delete().eq("location_id", location.id).eq("plate_number", plate);

const inId = eventId();
const { data: inEvent, error: inError } = await supabase.rpc("process_gate_event", { p_event_id: inId, p_location_id: location.id, p_gate_id: gate.id, p_plate_number: plate, p_driver_name: "CROSS-DAY TEST", p_direction: "IN", p_device_id: "CROSS-DAY-TEST", p_device_time: yesterday.toISOString(), p_operator_id: operator.id, p_notes: "CROSS_DAY_OUT_TEST_V2" });
assert.ifError(inError);
assert.equal(inEvent?.[0]?.result, "AUTHORIZED");
assert.equal(inEvent?.[0]?.in_event_id, inId);

const outId = eventId();
const { data: outEvent, error: outError } = await supabase.rpc("process_gate_event", { p_event_id: outId, p_location_id: location.id, p_gate_id: gate.id, p_plate_number: plate, p_driver_name: "CROSS-DAY TEST", p_direction: "OUT", p_device_id: "CROSS-DAY-TEST", p_device_time: now.toISOString(), p_operator_id: operator.id, p_notes: "CROSS_DAY_OUT_TEST_V2" });
assert.ifError(outError);
assert.equal(outEvent?.[0]?.result, "AUTHORIZED");
assert.equal(outEvent?.[0]?.in_event_id, inId);

const { data: active, error: activeError } = await supabase.from("active_vehicle_state").select("in_event_id").eq("location_id", location.id).eq("plate_number", plate).maybeSingle();
assert.ifError(activeError);
assert.equal(active, null);

console.log(JSON.stringify({ PASS: true, in_event_id: inId, in_device_time: yesterday.toISOString(), out_event_id: outId, out_device_time: now.toISOString(), out_linked_to: outEvent?.[0]?.in_event_id, active_after_out: null }, null, 2));