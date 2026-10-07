#!/usr/bin/env node

import assert from "node:assert/strict";
import {
  captureRoute,
  graceDate,
  liveActivityContentState,
  unixSeconds,
} from "../supabase/functions/dispatch-prompts/live-activity-payload.ts";

const deadline = "2027-01-15T08:10:00.000Z";
const expectedDeadline = 1_800_000_600;
const dismissal = graceDate(deadline);
const state = liveActivityContentState(deadline, 2, false, false, dismissal);

assert.deepEqual(state, {
  endsAt: expectedDeadline,
  responseCount: 2,
  hasSubmitted: false,
  allowsLateBlessings: false,
  dismissesAt: expectedDeadline + 180,
});
assert.equal(unixSeconds(new Date(deadline)), expectedDeadline);
assert.throws(() => unixSeconds("not-a-date"), /Invalid Live Activity date/);
assert.equal(unixSeconds(dismissal), expectedDeadline + 180);
assert.deepEqual(Object.keys(state).sort(), [
  "allowsLateBlessings",
  "dismissesAt",
  "endsAt",
  "hasSubmitted",
  "responseCount",
]);
assert.equal(
  captureRoute("circle-id", "prompt-id"),
  "blessingcircle://today/capture?circle=circle-id&prompt=prompt-id",
);

console.log("APNs Live Activity payload contract passed.");
