#!/usr/bin/env node

import assert from "node:assert/strict";
import {
  liveActivityContentState,
  unixSeconds,
} from "../supabase/functions/dispatch-prompts/live-activity-payload.ts";

const deadline = "2027-01-15T08:10:00.000Z";
const expectedDeadline = 1_800_000_600;
const state = liveActivityContentState(deadline, 2, false);

assert.deepEqual(state, {
  endsAt: expectedDeadline,
  responseCount: 2,
  hasSubmitted: false,
});
assert.equal(unixSeconds(new Date(deadline)), expectedDeadline);
assert.throws(() => unixSeconds("not-a-date"), /Invalid Live Activity date/);
assert.deepEqual(Object.keys(state).sort(), ["endsAt", "hasSubmitted", "responseCount"]);

console.log("APNs Live Activity payload contract passed.");
