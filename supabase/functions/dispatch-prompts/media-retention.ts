/** Both gates are required: an enabled flag alone must never start historical cleanup. */
export function mediaRetentionMayRun(enabled: string | undefined, startAt: string | undefined, now: number): boolean {
  if (enabled !== "true" || !startAt || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(startAt)) return false;
  const start = Date.parse(startAt);
  return Number.isFinite(start) && Number.isFinite(now) && now >= start;
}
