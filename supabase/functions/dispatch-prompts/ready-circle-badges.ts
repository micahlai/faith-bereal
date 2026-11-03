export type ReadyCircleBadgeClaim = {
  device_id: string;
  apns_token: string;
  environment: "sandbox" | "production";
  badge_count: number;
  lease_token: string;
};

export function readyCircleBadgePayload(count: number): { aps: { badge: number } } {
  if (!Number.isSafeInteger(count) || count < 0) throw new Error("Invalid badge count");
  return { aps: { badge: count } };
}

export async function deliverReadyCircleBadges(
  claims: ReadyCircleBadgeClaim[],
  operations: {
    send: (claim: ReadyCircleBadgeClaim, payload: ReturnType<typeof readyCircleBadgePayload>) => Promise<void>;
    complete: (claim: ReadyCircleBadgeClaim, success: boolean) => Promise<void>;
    invalidToken: (claim: ReadyCircleBadgeClaim, error: unknown) => Promise<void>;
  },
): Promise<{ delivered: number; failed: number }> {
  const results = await Promise.allSettled(claims.map(async (claim) => {
    let sent = false;
    try {
      await operations.send(claim, readyCircleBadgePayload(claim.badge_count));
      sent = true;
    } catch (error) {
      await operations.invalidToken(claim, error);
    } finally {
      await operations.complete(claim, sent);
    }
    return sent;
  }));
  const delivered = results.filter((result) => result.status === "fulfilled" && result.value).length;
  return { delivered, failed: results.length - delivered };
}
