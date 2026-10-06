import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type Prompt = {
  id: string;
  circle_id: string;
  starts_at: string;
  ends_at: string;
  dispatch_key: string;
  response_window_minutes: number;
};

type Device = {
  id: string;
  user_id: string;
  apns_token: string | null;
  push_to_start_token: string | null;
  environment: "sandbox" | "production";
};

type DeviceTokenField = "apns_token" | "push_to_start_token";

class APNsDeliveryError extends Error {
  constructor(
    readonly status: number,
    readonly reason: string,
  ) {
    super(`APNs ${status}: ${reason}`);
    this.name = "APNsDeliveryError";
  }
}

type ActivityRegistration = {
  id: string;
  prompt_id: string;
  user_id: string;
  push_token: string;
  environment: "sandbox" | "production";
};

const required = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const supabaseURL = required("SUPABASE_URL");
const serviceRoleKey = required("SUPABASE_SERVICE_ROLE_KEY");
const anonKey = required("SUPABASE_ANON_KEY");
const dispatchSecret = required("DISPATCH_SECRET");
const teamID = required("APNS_TEAM_ID");
const keyID = required("APNS_KEY_ID");
const bundleID = required("APNS_BUNDLE_ID");
const privateKeyPEM = required("APNS_PRIVATE_KEY").replaceAll("\\n", "\n");
const admin = createClient(supabaseURL, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function configuredSecretAPIKeys(): Set<string> {
  const rawValue = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!rawValue) return new Set();
  try {
    const parsed = JSON.parse(rawValue) as unknown;
    const values = Array.isArray(parsed)
      ? parsed
      : parsed && typeof parsed === "object"
      ? Object.values(parsed)
      : [];
    return new Set(values.filter((value): value is string => typeof value === "string"));
  } catch {
    console.error(JSON.stringify({ event: "invalid_supabase_secret_keys_configuration" }));
    return new Set();
  }
}

const scheduledAPIKeys = configuredSecretAPIKeys();

function hasScheduledCredential(request: Request): boolean {
  if (request.headers.get("x-dispatch-secret") === dispatchSecret) return true;
  const apiKey = request.headers.get("apikey");
  return apiKey === serviceRoleKey || (apiKey !== null && scheduledAPIKeys.has(apiKey));
}

let cachedToken: { value: string; createdAt: number } | undefined;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.createdAt < 50 * 60) return cachedToken.value;
  const key = await importPKCS8(privateKeyPEM, "ES256");
  const value = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt(now)
    .sign(key);
  cachedToken = { value, createdAt: now };
  return value;
}

async function sendAPNs(
  token: string,
  environment: Device["environment"],
  topic: string,
  pushType: "alert" | "liveactivity",
  payload: unknown,
): Promise<void> {
  const host = environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken()}`,
      "apns-topic": topic,
      "apns-push-type": pushType,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    let reason = "Unknown";
    try {
      const body = await response.json() as { reason?: string };
      reason = body.reason ?? reason;
    } catch {
      // APNs normally returns JSON. Avoid logging a token or an arbitrary body.
    }
    throw new APNsDeliveryError(response.status, reason);
  }
}

function permanentlyInvalidToken(error: unknown): boolean {
  return error instanceof APNsDeliveryError && (
    error.status === 410 ||
    (error.status === 400 && ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(error.reason))
  );
}

async function clearInvalidDeviceTokens(
  devices: Device[],
  invalidByDevice: Map<string, Set<DeviceTokenField>>,
): Promise<void> {
  const devicesByID = new Map(devices.map((device) => [device.id, device]));
  for (const [deviceID, fields] of invalidByDevice) {
    const device = devicesByID.get(deviceID);
    if (!device) continue;

    const update: Record<string, string | null> = {};
    for (const field of fields) update[field] = null;
    const hasAPNsToken = device.apns_token !== null && !fields.has("apns_token");
    const hasLiveActivityToken = device.push_to_start_token !== null && !fields.has("push_to_start_token");
    if (!hasAPNsToken && !hasLiveActivityToken) update.revoked_at = new Date().toISOString();

    const { error } = await admin.from("device_registrations").update(update).eq("id", deviceID);
    if (error) {
      console.error(JSON.stringify({
        event: "device_token_cleanup_failed",
        deviceID,
        message: error.message,
      }));
    }
  }
}

type DispatchOutcome = {
  delivered: number;
  attempted: number;
  failed: number;
  registeredDevices: number;
  memberCount: number;
};

async function dispatchPrompt(prompt: Prompt): Promise<DispatchOutcome> {
  const { data: circle, error: circleError } = await admin
    .from("circles")
    .select("name")
    .eq("id", prompt.circle_id)
    .single();
  if (circleError) throw circleError;

  const { data: memberships, error: membershipError } = await admin
    .from("circle_members")
    .select("user_id")
    .eq("circle_id", prompt.circle_id)
    .is("removed_at", null);
  if (membershipError) throw membershipError;
  const userIDs = (memberships ?? []).map((row) => row.user_id);
  if (userIDs.length === 0) {
    return { delivered: 0, attempted: 0, failed: 0, registeredDevices: 0, memberCount: 0 };
  }

  const { data: devices, error: deviceError } = await admin
    .from("device_registrations")
    .select("id, user_id, apns_token, push_to_start_token, environment")
    .in("user_id", userIDs)
    .is("revoked_at", null);
  if (deviceError) throw deviceError;
  const activeDevices = (devices ?? []) as Device[];

  const timestamp = Math.floor(Date.now() / 1000);
  const endsAt = Math.floor(new Date(prompt.ends_at).getTime() / 1000);
  const windowLabel = prompt.response_window_minutes === 1
    ? "one minute"
    : `${prompt.response_window_minutes} minutes`;
  const sends = activeDevices.flatMap((device) => {
    const deviceSends: Array<{
      deviceID: string;
      tokenField: DeviceTokenField;
      promise: Promise<void>;
    }> = [];
    if (device.apns_token) {
      deviceSends.push({
        deviceID: device.id,
        tokenField: "apns_token",
        promise: sendAPNs(device.apns_token, device.environment, bundleID, "alert", {
          aps: {
            alert: { title: `${circle.name} is ready`, body: `You have ${windowLabel} to share today’s blessing.` },
            sound: "default",
            "thread-id": prompt.circle_id,
            "interruption-level": "time-sensitive",
          },
          route: `blessingcircle://today/capture?circle=${prompt.circle_id}`,
          prompt_id: prompt.id,
        }),
      });
    }
    if (device.push_to_start_token) {
      deviceSends.push({
        deviceID: device.id,
        tokenField: "push_to_start_token",
        promise: sendAPNs(
          device.push_to_start_token,
          device.environment,
          `${bundleID}.push-type.liveactivity`,
          "liveactivity",
          {
            aps: {
              timestamp,
              event: "start",
              "input-push-token": 1,
              "attributes-type": "PromptActivityAttributes",
              attributes: { promptID: prompt.id, circleName: circle.name },
              "content-state": { endsAt, responseCount: 0, hasSubmitted: false },
              alert: {
                title: `${circle.name} is ready`,
                body: `You have ${windowLabel} to share today’s blessing.`,
                sound: "default",
              },
            },
          },
        ),
      });
    }
    return deviceSends;
  });
  const results = await Promise.allSettled(sends.map((send) => send.promise));

  const failures = results.filter((result) => result.status === "rejected");
  const invalidByDevice = new Map<string, Set<DeviceTokenField>>();
  results.forEach((result, index) => {
    if (result.status !== "rejected" || !permanentlyInvalidToken(result.reason)) return;
    const send = sends[index];
    const fields = invalidByDevice.get(send.deviceID) ?? new Set<DeviceTokenField>();
    fields.add(send.tokenField);
    invalidByDevice.set(send.deviceID, fields);
  });
  if (invalidByDevice.size > 0) await clearInvalidDeviceTokens(activeDevices, invalidByDevice);
  if (failures.length > 0) {
    console.error(JSON.stringify({
      event: "apns_dispatch_failures",
      promptID: prompt.id,
      circleID: prompt.circle_id,
      failures: failures.map((result) =>
        result.status === "rejected"
          ? (result.reason instanceof Error ? result.reason.message : String(result.reason))
          : ""
      ),
    }));
  }
  return {
    delivered: results.length - failures.length,
    attempted: results.length,
    failed: failures.length,
    registeredDevices: activeDevices.length,
    memberCount: userIDs.length,
};
}

async function markPromptOpen(promptID: string, outcome: DispatchOutcome): Promise<void> {
  const { error } = await admin
    .from("daily_prompts")
    .update({
      state: "open",
      failure_reason: outcome.failed > 0
        ? `${outcome.failed} of ${outcome.attempted} APNs requests failed`
        : null,
    })
    .eq("id", promptID);
  if (error) throw error;
}

async function markPromptFailed(promptID: string, message: string): Promise<void> {
  const { error } = await admin
    .from("daily_prompts")
    .update({ state: "failed", failure_reason: message.slice(0, 500) })
    .eq("id", promptID);
  if (error) {
    console.error(JSON.stringify({ event: "prompt_failure_update_failed", promptID, message: error.message }));
  }
}

async function updateOpenActivities(): Promise<void> {
  const { data: prompts, error: promptError } = await admin
    .from("daily_prompts")
    .select("id, ends_at")
    .eq("state", "open")
    .gt("ends_at", new Date().toISOString());
  if (promptError) throw promptError;

  for (const prompt of prompts ?? []) {
    const { data: registrations, error: registrationError } = await admin
      .from("activity_registrations")
      .select("id, prompt_id, user_id, push_token, environment")
      .eq("prompt_id", prompt.id)
      .is("ended_at", null);
    if (registrationError) throw registrationError;
    if (!registrations?.length) continue;

    const { data: blessings, error: blessingError } = await admin
      .from("blessings")
      .select("author_id")
      .eq("prompt_id", prompt.id);
    if (blessingError) throw blessingError;
    const authors = new Set((blessings ?? []).map((row) => row.author_id));
    const timestamp = Math.floor(Date.now() / 1000);
    const endsAt = Math.floor(new Date(prompt.ends_at).getTime() / 1000);

    await Promise.allSettled((registrations as ActivityRegistration[]).map((registration) =>
      sendAPNs(
        registration.push_token,
        registration.environment,
        `${bundleID}.push-type.liveactivity`,
        "liveactivity",
        {
          aps: {
            timestamp,
            event: "update",
            "content-state": {
              endsAt,
              responseCount: authors.size,
              hasSubmitted: authors.has(registration.user_id),
            },
          },
        },
      )
    ));
  }
}

async function closeExpiredPrompts(): Promise<void> {
  const now = new Date();
  const { data: prompts, error: promptError } = await admin
    .from("daily_prompts")
    .select("id, ends_at")
    .in("state", ["open", "dispatching"])
    .lte("ends_at", now.toISOString());
  if (promptError) throw promptError;

  for (const prompt of prompts ?? []) {
    const { data: registrations, error: registrationError } = await admin
      .from("activity_registrations")
      .select("id, prompt_id, user_id, push_token, environment")
      .eq("prompt_id", prompt.id)
      .is("ended_at", null);
    if (registrationError) throw registrationError;

    const { data: blessings, error: blessingError } = await admin
      .from("blessings")
      .select("author_id")
      .eq("prompt_id", prompt.id);
    if (blessingError) throw blessingError;
    const authors = new Set((blessings ?? []).map((row) => row.author_id));
    const timestamp = Math.floor(now.getTime() / 1000);
    const endsAt = Math.floor(new Date(prompt.ends_at).getTime() / 1000);

    await Promise.allSettled(((registrations ?? []) as ActivityRegistration[]).map((registration) =>
      sendAPNs(
        registration.push_token,
        registration.environment,
        `${bundleID}.push-type.liveactivity`,
        "liveactivity",
        {
          aps: {
            timestamp,
            event: "end",
            "dismissal-date": timestamp + 60,
            "content-state": {
              endsAt,
              responseCount: authors.size,
              hasSubmitted: authors.has(registration.user_id),
            },
          },
        },
      )
    ));

    if (registrations?.length) {
      await admin
        .from("activity_registrations")
        .update({ ended_at: now.toISOString() })
        .in("id", registrations.map((registration) => registration.id));
    }
  }

  if (prompts?.length) {
    await admin
      .from("daily_prompts")
      .update({ state: "closed", closed_at: now.toISOString() })
      .in("id", prompts.map((prompt) => prompt.id));
  }
}

Deno.serve(async (request) => {
  const isScheduledDispatch = hasScheduledCredential(request);
  if (!isScheduledDispatch) {
    const authorization = request.headers.get("authorization");
    if (!authorization?.toLowerCase().startsWith("bearer ")) {
      return Response.json({ error: "Authentication required" }, { status: 401 });
    }

    let body: { action?: string; circle_id?: string };
    try {
      body = await request.json();
    } catch {
      return Response.json({ error: "Invalid request body" }, { status: 400 });
    }
    if (body.action !== "force" || !body.circle_id) {
      return Response.json({ error: "Unsupported action" }, { status: 400 });
    }

    const userClient = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: prompt, error: promptError } = await userClient
      .rpc("force_circle_prompt", { p_circle_id: body.circle_id })
      .single();
    if (promptError) {
      const status = promptError.message.includes("owner") ? 403 : 400;
      return Response.json({ error: promptError.message }, { status });
    }

    const forcedPrompt = prompt as Prompt;
    try {
      const outcome = await dispatchPrompt(forcedPrompt);
      await markPromptOpen(forcedPrompt.id, outcome);
      return Response.json({ promptID: forcedPrompt.id, ...outcome });
    } catch (dispatchError) {
      const message = dispatchError instanceof Error ? dispatchError.message : String(dispatchError);
      await markPromptFailed(forcedPrompt.id, message);
      return Response.json({ error: "Notification dispatch failed" }, { status: 502 });
    }
  }

  const { error: ensureError } = await admin.rpc("ensure_tomorrow_prompts");
  if (ensureError) return Response.json({ error: ensureError.message }, { status: 500 });
  const { data, error } = await admin.rpc("claim_due_prompts", { p_limit: 100 });
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const outcomes = [];
  for (const prompt of (data ?? []) as Prompt[]) {
    try {
      const outcome = await dispatchPrompt(prompt);
      await markPromptOpen(prompt.id, outcome);
      outcomes.push({ promptID: prompt.id, ...outcome });
    } catch (dispatchError) {
      const message = dispatchError instanceof Error ? dispatchError.message : String(dispatchError);
      await markPromptFailed(prompt.id, message);
      outcomes.push({ promptID: prompt.id, error: message });
    }
  }
  await updateOpenActivities();
  await closeExpiredPrompts();

  return Response.json({ claimed: outcomes.length, outcomes });
});
