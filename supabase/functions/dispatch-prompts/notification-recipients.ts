import type { CircleActivityEvent } from "./notification-payload.ts";

// Membership and sender exclusions are applied by the dispatch query. Only
// blessing/response alerts honor the per-circle activity preference.
export function circleActivityMemberIDs(
  eventType: CircleActivityEvent,
  memberships: { user_id: string; notify_on_circle_activity: boolean }[],
): Set<string> {
  return new Set(memberships
    .filter((member) => eventType === "member_nudged" || member.notify_on_circle_activity)
    .map((member) => member.user_id));
}
