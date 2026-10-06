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
  user_id: string;
  apns_token: string | null;
  push_to_start_token: string | null;
  environment: "sandbox" | "production";
};

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
    throw new Error(`APNs ${response.status}: ${await response.text()}`);
  }
}

type DispatchOutcome = {
  delivered: number;
  attempted: number;
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
    return { delivered: 0, attempted: 0, registeredDevices: 0, memberCount: 0 };
  }

  const { data: devices, error: deviceError } = await admin
    .from("device_registrations")
    .select("user_id, apns_token, push_to_start_token, environment")
    .in("user_id", userIDs)
    .is("revoked_at", null);
  if (deviceError) throw deviceError;
  const activeDevices = (devices ?? []) as Device[];

  const timestamp = Math.floor(Date.now() / 1000);
  const endsAt = Math.floor(new Date(prompt.ends_at).getTime() / 1000);
  const windowLabel = prompt.response_window_minutes === 1
    ? "one minute"
    : `${prompt.response_window_minutes} minutes`;
  const results = await Promise.allSettled(activeDevices.flatMap((device) => {
    const sends: Promise<void>[] = [];
    if (device.apns_token) {
      sends.push(sendAPNs(device.apns_token, device.environment, bundleID, "alert", {
        aps: {
          alert: { title: `${circle.name} is ready`, body: `You have ${windowLabel} to share today’s blessing.` },
          sound: "default",
          "thread-id": prompt.circle_id,
          "interruption-level": "time-sensitive",
        },
        route: `blessingcircle://today/capture?circle=${prompt.circle_id}`,
        prompt_id: prompt.id,
      }));
    }
    if (device.push_to_start_token) {
      sends.push(sendAPNs(
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
      ));
    }
    return sends;
  }));

  const failures = results.filter((result) => result.status === "rejected");
  if (failures.length === results.length && results.length > 0) {
    throw new Error(`All ${failures.length} APNs requests failed`);
  }
  return {
    delivered: results.length - failures.length,
    attempted: results.length,
    registeredDevices: activeDevices.length,
    memberCount: userIDs.length,
  };
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
  const isScheduledDispatch = request.headers.get("x-dispatch-secret") === dispatchSecret;
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

    try {
      const outcome = await dispatchPrompt(prompt as Prompt);
      await admin
        .from("daily_prompts")
        .update({ state: "open", failure_reason: null })
        .eq("id", prompt.id);
      return Response.json({ promptID: prompt.id, ...outcome });
    } catch (dispatchError) {
      const message = dispatchError instanceof Error ? dispatchError.message : String(dispatchError);
      await admin
        .from("daily_prompts")
        .update({ state: "failed", failure_reason: message.slice(0, 500) })
        .eq("id", prompt.id);
      return Response.json({ error: "Notification dispatch failed" }, { status: 502 });
    }
  }

  await admin.rpc("ensure_tomorrow_prompts");
  const { data, error } = await admin.rpc("claim_due_prompts", { p_limit: 100 });
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const outcomes = [];
  for (const prompt of (data ?? []) as Prompt[]) {
    try {
      const outcome = await dispatchPrompt(prompt);
      await admin.from("daily_prompts").update({ state: "open", failure_reason: null }).eq("id", prompt.id);
      outcomes.push({ promptID: prompt.id, ...outcome });
    } catch (dispatchError) {
      const message = dispatchError instanceof Error ? dispatchError.message : String(dispatchError);
      await admin.from("daily_prompts").update({ state: "failed", failure_reason: message.slice(0, 500) }).eq("id", prompt.id);
      outcomes.push({ promptID: prompt.id, error: message });
    }
  }
  await updateOpenActivities();
  await closeExpiredPrompts();

  return Response.json({ claimed: outcomes.length, outcomes });
});
