export type LiveActivityContentState = {
  endsAt: number;
  responseCount: number;
  hasSubmitted: boolean;
};

export function unixSeconds(value: string | Date): number {
  const milliseconds = value instanceof Date ? value.getTime() : new Date(value).getTime();
  if (!Number.isFinite(milliseconds)) throw new Error("Invalid Live Activity date");
  return Math.floor(milliseconds / 1000);
}

export function liveActivityContentState(
  endsAt: string | Date,
  responseCount: number,
  hasSubmitted: boolean,
): LiveActivityContentState {
  return {
    endsAt: unixSeconds(endsAt),
    responseCount,
    hasSubmitted,
  };
}
