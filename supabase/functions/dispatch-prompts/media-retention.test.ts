import { mediaRetentionMayRun } from "./media-retention.ts";
Deno.test("cleanup needs both explicit enablement and a valid UTC release grace deadline", () => {
  const start = "2026-11-10T12:00:00Z", now = Date.parse(start);
  for (const value of [undefined, "", "tomorrow", "2026-11-10", "2026-11-10T12:00:00"]) {
    if (mediaRetentionMayRun("true", value, now)) throw new Error("Missing/ambiguous date activated cleanup");
  }
  if (mediaRetentionMayRun("false", start, now) || mediaRetentionMayRun(undefined, start, now)) throw new Error("Disabled cleanup ran");
  if (mediaRetentionMayRun("true", start, now - 1)) throw new Error("Cleanup ran before grace deadline");
  if (!mediaRetentionMayRun("true", start, now) || !mediaRetentionMayRun("true", start, now + 1)) throw new Error("Eligible cleanup did not run");
});
