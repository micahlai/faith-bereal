export type LiveActivityContentState = {
  endsAt: number;
  responseCount: number;
  hasSubmitted: boolean;
  allowsLateBlessings: boolean;
  dismissesAt: number | null;
};

export const LIVE_ACTIVITY_GRACE_SECONDS = 3 * 60;

export function unixSeconds(value: string | Date): number {
  const milliseconds = value instanceof Date ? value.getTime() : new Date(value).getTime();
  if (!Number.isFinite(milliseconds)) throw new Error("Invalid Live Activity date");
  return Math.floor(milliseconds / 1000);
}

export function liveActivityContentState(
  endsAt: string | Date,
  responseCount: number,
  hasSubmitted: boolean,
  allowsLateBlessings: boolean,
  dismissesAt: string | Date | null,
): LiveActivityContentState {
  return {
    endsAt: unixSeconds(endsAt),
    responseCount,
    hasSubmitted,
    allowsLateBlessings,
    dismissesAt: dismissesAt === null ? null : unixSeconds(dismissesAt),
  };
}

export function graceDate(value: string | Date): Date {
  const milliseconds = value instanceof Date ? value.getTime() : new Date(value).getTime();
  if (!Number.isFinite(milliseconds)) throw new Error("Invalid Live Activity date");
  return new Date(milliseconds + LIVE_ACTIVITY_GRACE_SECONDS * 1000);
}

export function captureRoute(circleID: string, promptID: string): string {
  return `blessingcircle://today/capture?circle=${circleID}&prompt=${promptID}`;
}
