import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";
import {
  captureRoute,
  graceDate,
  liveActivityContentState,
  unixSeconds,
} from "./live-activity-payload.ts";
import {
  circleActivityBody,
  notificationMedia,
  promptReminder,
} from "./notification-payload.ts";

type Prompt = {
  id: string;
  circle_id: string;
  starts_at: string;
  ends_at: string;
  dispatch_key: string;
  response_window_minutes: number;
  kind: "daily" | "end_of_day";
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

type BlessingAuthor = {
  author_id: string;
  submitted_at: string;
};

type CircleNotification = {
  id: string;
  event_type: "blessing_shared" | "response_shared";
  blessing_id: string;
  response_id: string | null;
};

type NotificationBlessing = {
  id: string;
  prompt_id: string;
  author_id: string;
  body: string;
  capture_mode: string;
  thumbnail_path: string | null;
  photo_path: string | null;
  scripture_book_name: string | null;
  scripture_chapter: number | null;
  scripture_verse_start: number | null;
  scripture_verse_end: number | null;
};

type NotificationResponse = {
  id: string;
  author_id: string;
  body: string;
  submitted_at: string;
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
const privilegedAPIKey = scheduledAPIKeys.values().next().value ?? serviceRoleKey;
const admin = createClient(supabaseURL, privilegedAPIKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function hasScheduledCredential(request: Request): boolean {
  if (request.headers.get("x-dispatch-secret") === dispatchSecret) return true;
  const apiKey = request.headers.get("apikey");
  return apiKey === serviceRoleKey || (apiKey !== null && scheduledAPIKeys.has(apiKey));
}

let cachedToken: { value: string; createdAt: number } | undefined;

async function providerToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.createdAt < 45 * 60) return cachedToken.value;
  const key = await importPKCS8(privateKeyPEM, "ES256");
  const candidate = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID)
    .setIssuedAt(now)
    .sign(key);
  const { data, error } = await admin
    .rpc("claim_apns_provider_token", { p_token: candidate })
    .single();
  if (error) throw error;

  const stored = data as { token: string; created_at: string };
  const createdAt = Math.floor(new Date(stored.created_at).getTime() / 1000);
  if (!stored.token || !Number.isFinite(createdAt)) {
    throw new Error("Invalid APNs provider token cache response");
  }
  cachedToken = { value: stored.token, createdAt };
  return stored.token;
}

async function sendAPNs(
  token: string,
  environment: Device["environment"],
  topic: string,
  pushType: "alert" | "liveactivity",
  payload: unknown,
  collapseID?: string,
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
      ...(collapseID ? { "apns-collapse-id": collapseID } : {}),
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

async function signedStorageURL(bucket: string, path: string | null): Promise<string | null> {
  if (!path) return null;
  const { data, error } = await admin.storage.from(bucket).createSignedUrl(path, 15 * 60);
  if (error) {
    console.error(JSON.stringify({ event: "notification_image_signing_failed", bucket, message: error.message }));
    return null;
  }
  return data.signedUrl;
}

function blessingRoute(circleID: string, blessingID: string): string {
  return `blessingcircle://blessing/${blessingID}?circle=${circleID}`;
}

function todayRoute(circleID: string, promptID: string): string {
  return `blessingcircle://today?circle=${circleID}&prompt=${promptID}`;
}

async function dispatchCircleNotification(notification: CircleNotification): Promise<void> {
  const { data: blessingData, error: blessingError } = await admin
    .from("blessings")
    .select(
      "id, prompt_id, author_id, body, capture_mode, thumbnail_path, photo_path, scripture_book_name, scripture_chapter, scripture_verse_start, scripture_verse_end",
    )
    .eq("id", notification.blessing_id)
    .single();
  if (blessingError) throw blessingError;
  const blessing = blessingData as NotificationBlessing;

  const { data: prompt, error: promptError } = await admin
    .from("daily_prompts")
    .select("circle_id")
    .eq("id", blessing.prompt_id)
    .single();
  if (promptError) throw promptError;

  const { data: circle, error: circleError } = await admin
    .from("circles")
    .select("name")
    .eq("id", prompt.circle_id)
    .single();
  if (circleError) throw circleError;

  let senderID = blessing.author_id;
  let response: NotificationResponse | null = null;
  if (notification.event_type === "response_shared") {
    const { data, error } = await admin
      .from("blessing_responses")
      .select("id, author_id, body, submitted_at")
      .eq("id", notification.response_id!)
      .single();
    if (error) throw error;
    response = data as NotificationResponse;
    senderID = response.author_id;
  }

  const { data: sender, error: senderError } = await admin
    .from("profiles")
    .select("display_name, avatar_path")
    .eq("id", senderID)
    .single();
  if (senderError) throw senderError;

  const { data: memberships, error: membershipError } = await admin
    .from("circle_members")
    .select("user_id")
    .eq("circle_id", prompt.circle_id)
    .eq("notify_on_circle_activity", true)
    .is("removed_at", null)
    .neq("user_id", senderID);
  if (membershipError) throw membershipError;
  const enabledMemberIDs = new Set((memberships ?? []).map((row) => row.user_id));

  let recipientIDs: string[];
  const submittedByRecipient = new Set<string>();
  if (notification.event_type === "blessing_shared") {
    recipientIDs = [...enabledMemberIDs];
    if (recipientIDs.length > 0) {
      const { data: submissions, error: submissionError } = await admin
        .from("blessings")
        .select("author_id")
        .eq("prompt_id", blessing.prompt_id)
        .in("author_id", recipientIDs);
      if (submissionError) throw submissionError;
      for (const submission of submissions ?? []) submittedByRecipient.add(submission.author_id);
    }
  } else {
    const { data: priorResponses, error: responseError } = await admin
      .from("blessing_responses")
      .select("author_id")
      .eq("blessing_id", blessing.id)
      .lt("submitted_at", response!.submitted_at)
      .neq("author_id", senderID);
    if (responseError) throw responseError;
    const followers = new Set<string>([blessing.author_id]);
    for (const priorResponse of priorResponses ?? []) followers.add(priorResponse.author_id);
    followers.delete(senderID);
    recipientIDs = [...followers].filter((id) => enabledMemberIDs.has(id));
  }

  if (recipientIDs.length === 0) return;
  const { data: devices, error: deviceError } = await admin
    .from("device_registrations")
    .select("id, user_id, apns_token, push_to_start_token, environment")
    .in("user_id", recipientIDs)
    .is("revoked_at", null);
  if (deviceError) throw deviceError;
  const activeDevices = ((devices ?? []) as Device[]).filter((device) => device.apns_token !== null);
  if (activeDevices.length === 0) return;

  const senderAvatarURL = await signedStorageURL("avatars", sender.avatar_path);
  const blessingMedia = notificationMedia({
    eventType: notification.event_type,
    unlocked: true,
    captureMode: blessing.capture_mode,
    thumbnailPath: blessing.thumbnail_path,
    photoPath: blessing.photo_path,
    senderAvatarPath: sender.avatar_path,
  });
  const blessingMediaURL = blessingMedia?.bucket === "blessing-media"
    ? await signedStorageURL(blessingMedia.bucket, blessingMedia.path)
    : senderAvatarURL;
  const invalidByDevice = new Map<string, Set<DeviceTokenField>>();
  const results = await Promise.allSettled(activeDevices.map((device) => {
    const unlocked = notification.event_type === "response_shared" || submittedByRecipient.has(device.user_id);
    const body = circleActivityBody({
      eventType: notification.event_type,
      senderName: sender.display_name,
      message: notification.event_type === "blessing_shared" ? blessing.body : response!.body,
      unlocked,
      scripture: {
        bookName: blessing.scripture_book_name,
        chapter: blessing.scripture_chapter,
        verseStart: blessing.scripture_verse_start,
        verseEnd: blessing.scripture_verse_end,
      },
    });
    const richMediaURL = unlocked ? blessingMediaURL : null;
    const route = notification.event_type === "blessing_shared" && !unlocked
      ? todayRoute(prompt.circle_id, blessing.prompt_id)
      : blessingRoute(prompt.circle_id, blessing.id);
    return sendAPNs(
      device.apns_token!,
      device.environment,
      bundleID,
      "alert",
      {
        aps: {
          alert: { title: circle.name, body },
          sound: "default",
          "mutable-content": 1,
          category: "CIRCLE_ACTIVITY",
          "thread-id": prompt.circle_id,
        },
        route,
        notification_kind: notification.event_type,
        sender_id: senderID,
        sender_name: sender.display_name,
        circle_id: prompt.circle_id,
        circle_name: circle.name,
        ...(richMediaURL ? { rich_media_url: richMediaURL } : {}),
        blessing_id: blessing.id,
      },
      notification.id,
    );
  }));

  results.forEach((result, index) => {
    if (result.status !== "rejected" || !permanentlyInvalidToken(result.reason)) return;
    invalidByDevice.set(activeDevices[index].id, new Set<DeviceTokenField>(["apns_token"]));
  });
  if (invalidByDevice.size > 0) await clearInvalidDeviceTokens(activeDevices, invalidByDevice);

  const failures = results.filter((result) => result.status === "rejected");
  if (failures.length > 0) {
    console.error(JSON.stringify({
      event: "circle_notification_delivery_failures",
      notificationID: notification.id,
      failures: failures.map((result) =>
        result.status === "rejected"
          ? (result.reason instanceof Error ? result.reason.message : String(result.reason))
          : ""
      ),
    }));
  }
}

async function processCircleNotifications(): Promise<void> {
  const { data, error } = await admin.rpc("claim_circle_notifications", { p_limit: 100 });
  if (error) throw error;

  for (const notification of (data ?? []) as CircleNotification[]) {
    try {
      await dispatchCircleNotification(notification);
      const { error: completeError } = await admin.rpc("complete_circle_notification", {
        p_id: notification.id,
        p_error: null,
      });
      if (completeError) throw completeError;
    } catch (notificationError) {
      const message = notificationError instanceof Error
        ? notificationError.message
        : String(notificationError);
      console.error(JSON.stringify({
        event: "circle_notification_failed",
        notificationID: notification.id,
        message,
      }));
      await admin.rpc("complete_circle_notification", {
        p_id: notification.id,
        p_error: message,
      });
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
    .select("name, allow_late_blessings")
    .eq("id", prompt.circle_id)
    .single();
  if (circleError) throw circleError;

  const { data: memberships, error: membershipError } = await admin
    .from("circle_members")
    .select("user_id, notify_on_end_of_day")
    .eq("circle_id", prompt.circle_id)
    .is("removed_at", null);
  if (membershipError) throw membershipError;
  const eligibleMemberships = prompt.kind === "end_of_day"
    ? (memberships ?? []).filter((row) => row.notify_on_end_of_day !== false)
    : (memberships ?? []);
  const userIDs = eligibleMemberships.map((row) => row.user_id);
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

  const timestamp = unixSeconds(new Date());
  const reminder = promptReminder({
    kind: prompt.kind,
    circleName: circle.name,
    responseWindowMinutes: prompt.response_window_minutes,
  });
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
            alert: reminder.alert,
            sound: "default",
            "mutable-content": 1,
            "thread-id": prompt.circle_id,
            "interruption-level": "time-sensitive",
          },
          route: captureRoute(prompt.circle_id, prompt.id),
          prompt_id: prompt.id,
        }, `prompt-${prompt.dispatch_key}`),
      });
    }
    if (reminder.startsLiveActivity && device.push_to_start_token) {
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
              "content-state": liveActivityContentState(
                prompt.ends_at,
                0,
                false,
                circle.allow_late_blessings,
                circle.allow_late_blessings ? null : graceDate(prompt.ends_at),
              ),
              alert: {
                ...reminder.alert,
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
    .select("id, circle_id, ends_at")
    .eq("state", "open")
    .eq("kind", "daily")
    .gt("ends_at", new Date().toISOString());
  if (promptError) throw promptError;

  for (const prompt of prompts ?? []) {
    const { data: circle, error: circleError } = await admin
      .from("circles")
      .select("allow_late_blessings")
      .eq("id", prompt.circle_id)
      .single();
    if (circleError) throw circleError;
    const { data: registrations, error: registrationError } = await admin
      .from("activity_registrations")
      .select("id, prompt_id, user_id, push_token, environment")
      .eq("prompt_id", prompt.id)
      .is("ended_at", null);
    if (registrationError) throw registrationError;
    if (!registrations?.length) continue;

    const { data: blessings, error: blessingError } = await admin
      .from("blessings")
      .select("author_id, submitted_at")
      .eq("prompt_id", prompt.id);
    if (blessingError) throw blessingError;
    const blessingByAuthor = new Map(
      ((blessings ?? []) as BlessingAuthor[]).map((row) => [row.author_id, row]),
    );
    const timestamp = unixSeconds(new Date());
    const activityUpdates = (registrations as ActivityRegistration[]).map((registration) => {
        const blessing = blessingByAuthor.get(registration.user_id);
        const dismissesAt = blessing
          ? graceDate(blessing.submitted_at)
          : circle.allow_late_blessings ? null : graceDate(prompt.ends_at);
        return {
          registrationID: registration.id,
          shouldEnd: blessing !== undefined,
          promise: sendAPNs(
            registration.push_token,
            registration.environment,
            `${bundleID}.push-type.liveactivity`,
            "liveactivity",
            {
              aps: {
                timestamp,
                event: blessing ? "end" : "update",
                ...(dismissesAt ? { "dismissal-date": unixSeconds(dismissesAt) } : {}),
                "content-state": liveActivityContentState(
                  prompt.ends_at,
                  blessingByAuthor.size,
                  blessing !== undefined,
                  circle.allow_late_blessings,
                  dismissesAt,
                ),
              },
            },
          ),
        };
      });
    const activityResults = await Promise.allSettled(activityUpdates.map((update) => update.promise));
    const endedRegistrationIDs = activityUpdates
      .filter((update, index) => update.shouldEnd && activityResults[index].status === "fulfilled")
      .map((update) => update.registrationID);
    if (endedRegistrationIDs.length > 0) {
      await admin
        .from("activity_registrations")
        .update({ ended_at: new Date().toISOString() })
        .in("id", endedRegistrationIDs);
    }
  }
}

async function closeExpiredPrompts(): Promise<void> {
  const now = new Date();
  const { data: prompts, error: promptError } = await admin
    .from("daily_prompts")
    .select("id, circle_id, ends_at, kind")
    .in("state", ["open", "dispatching"])
    .lte("ends_at", now.toISOString());
  if (promptError) throw promptError;

  for (const prompt of prompts ?? []) {
    if (prompt.kind !== "daily") continue;
    const { data: circle, error: circleError } = await admin
      .from("circles")
      .select("allow_late_blessings")
      .eq("id", prompt.circle_id)
      .single();
    if (circleError) throw circleError;
    const { data: registrations, error: registrationError } = await admin
      .from("activity_registrations")
      .select("id, prompt_id, user_id, push_token, environment")
      .eq("prompt_id", prompt.id)
      .is("ended_at", null);
    if (registrationError) throw registrationError;

    const { data: blessings, error: blessingError } = await admin
      .from("blessings")
      .select("author_id, submitted_at")
      .eq("prompt_id", prompt.id);
    if (blessingError) throw blessingError;
    const blessingByAuthor = new Map(
      ((blessings ?? []) as BlessingAuthor[]).map((row) => [row.author_id, row]),
    );
    const timestamp = unixSeconds(now);
    const activityUpdates = ((registrations ?? []) as ActivityRegistration[]).map((registration) => {
        const blessing = blessingByAuthor.get(registration.user_id);
        const remainsOpen = circle.allow_late_blessings && blessing === undefined;
        const dismissesAt = blessing
          ? graceDate(blessing.submitted_at)
          : remainsOpen ? null : graceDate(prompt.ends_at);
        return {
          registrationID: registration.id,
          shouldEnd: !remainsOpen,
          promise: sendAPNs(
            registration.push_token,
            registration.environment,
            `${bundleID}.push-type.liveactivity`,
            "liveactivity",
            {
              aps: {
                timestamp,
                event: remainsOpen ? "update" : "end",
                ...(dismissesAt ? { "dismissal-date": unixSeconds(dismissesAt) } : {}),
                "content-state": liveActivityContentState(
                  prompt.ends_at,
                  blessingByAuthor.size,
                  blessing !== undefined,
                  circle.allow_late_blessings,
                  dismissesAt,
                ),
              },
            },
          ),
        };
      });
    const activityResults = await Promise.allSettled(activityUpdates.map((update) => update.promise));
    const endedRegistrationIDs = activityUpdates
      .filter((update, index) => update.shouldEnd && activityResults[index].status === "fulfilled")
      .map((update) => update.registrationID);

    if (endedRegistrationIDs.length > 0) {
      await admin
        .from("activity_registrations")
        .update({ ended_at: now.toISOString() })
        .in("id", endedRegistrationIDs);
    }
  }

  if (prompts?.length) {
    await admin
      .from("daily_prompts")
      .update({ state: "closed", closed_at: now.toISOString() })
      .in("id", prompts.map((prompt) => prompt.id));
  }
}

async function reconcileLateActivities(): Promise<void> {
  const now = new Date();
  const { data: registrations, error: registrationError } = await admin
    .from("activity_registrations")
    .select("id, prompt_id, user_id, push_token, environment")
    .is("ended_at", null);
  if (registrationError) throw registrationError;
  if (!registrations?.length) return;

  const promptIDs = [...new Set(registrations.map((registration) => registration.prompt_id))];
  const { data: prompts, error: promptError } = await admin
    .from("daily_prompts")
    .select("id, circle_id, starts_at, ends_at, kind")
    .in("id", promptIDs)
    .lte("ends_at", now.toISOString());
  if (promptError) throw promptError;
  if (!prompts?.length) return;

  const circleIDs = [...new Set(prompts.map((prompt) => prompt.circle_id))];
  const { data: circles, error: circleError } = await admin
    .from("circles")
    .select("id, allow_late_blessings")
    .in("id", circleIDs);
  if (circleError) throw circleError;
  const allowsLateByCircle = new Map(
    (circles ?? []).map((circle) => [circle.id, circle.allow_late_blessings]),
  );
  const latePrompts = prompts.filter((prompt) =>
    prompt.kind === "daily" && allowsLateByCircle.get(prompt.circle_id) === true
  );
  if (latePrompts.length === 0) return;

  const latePromptIDs = latePrompts.map((prompt) => prompt.id);
  const { data: blessings, error: blessingError } = await admin
    .from("blessings")
    .select("prompt_id, author_id, submitted_at")
    .in("prompt_id", latePromptIDs);
  if (blessingError) throw blessingError;
  const blessingByPromptAndAuthor = new Map(
    ((blessings ?? []) as Array<BlessingAuthor & { prompt_id: string }>).map((blessing) => [
      `${blessing.prompt_id}:${blessing.author_id}`,
      blessing,
    ]),
  );

  const { data: startedPrompts, error: startedPromptError } = await admin
    .from("daily_prompts")
    .select("circle_id, starts_at")
    .in("circle_id", circleIDs)
    .eq("kind", "daily")
    .lte("starts_at", now.toISOString());
  if (startedPromptError) throw startedPromptError;

  const registrationsByPrompt = new Map<string, ActivityRegistration[]>();
  for (const registration of registrations as ActivityRegistration[]) {
    const values = registrationsByPrompt.get(registration.prompt_id) ?? [];
    values.push(registration);
    registrationsByPrompt.set(registration.prompt_id, values);
  }
  const timestamp = unixSeconds(now);

  for (const prompt of latePrompts) {
    const promptRegistrations = registrationsByPrompt.get(prompt.id) ?? [];
    if (promptRegistrations.length === 0) continue;
    const authorCount = (blessings ?? []).filter((blessing) => blessing.prompt_id === prompt.id).length;
    const replacementStart = (startedPrompts ?? [])
      .filter((candidate) =>
        candidate.circle_id === prompt.circle_id &&
        new Date(candidate.starts_at).getTime() > new Date(prompt.starts_at).getTime()
      )
      .map((candidate) => candidate.starts_at)
      .sort()[0];
    const activityUpdates = promptRegistrations.map((registration) => {
      const blessing = blessingByPromptAndAuthor.get(`${prompt.id}:${registration.user_id}`);
      const dismissesAt = blessing
        ? graceDate(blessing.submitted_at)
        : replacementStart ? graceDate(replacementStart) : null;
      const shouldEnd = dismissesAt !== null;
      return {
        registrationID: registration.id,
        shouldEnd,
        promise: sendAPNs(
          registration.push_token,
          registration.environment,
          `${bundleID}.push-type.liveactivity`,
          "liveactivity",
          {
            aps: {
              timestamp,
              event: shouldEnd ? "end" : "update",
              ...(dismissesAt ? { "dismissal-date": unixSeconds(dismissesAt) } : {}),
              "content-state": liveActivityContentState(
                prompt.ends_at,
                authorCount,
                blessing !== undefined,
                true,
                dismissesAt,
              ),
            },
          },
        ),
      };
    });
    const activityResults = await Promise.allSettled(activityUpdates.map((update) => update.promise));
    const endedRegistrationIDs = activityUpdates
      .filter((update, index) => update.shouldEnd && activityResults[index].status === "fulfilled")
      .map((update) => update.registrationID);

    if (endedRegistrationIDs.length > 0) {
      await admin
        .from("activity_registrations")
        .update({ ended_at: now.toISOString() })
        .in("id", endedRegistrationIDs);
    }
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
  await reconcileLateActivities();
  await processCircleNotifications();

  return Response.json({ claimed: outcomes.length, outcomes });
});
