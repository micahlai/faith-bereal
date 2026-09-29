import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

type Prompt = {
  id: string;
  circle_id: string;
  starts_at: string;
  ends_at: string;
  dispatch_key: string;
};

type Device = {
  user_id: string;
  apns_token: string | null;
  push_to_start_token: string | null;
  environment: "sandbox" | "production";
};

const required = (name: string): string => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};

const supabaseURL = required("SUPABASE_URL");
const serviceRoleKey = required("SUPABASE_SERVICE_ROLE_KEY");
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

async function dispatchPrompt(prompt: Prompt): Promise<number> {
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
  const userIDs = memberships.map((row) => row.user_id);
  if (userIDs.length === 0) return 0;

  const { data: devices, error: deviceError } = await admin
    .from("device_registrations")
    .select("user_id, apns_token, push_to_start_token, environment")
    .in("user_id", userIDs)
    .is("revoked_at", null);
  if (deviceError) throw deviceError;

  const timestamp = Math.floor(Date.now() / 1000);
  const endsAt = Math.floor(new Date(prompt.ends_at).getTime() / 1000);
  const results = await Promise.allSettled((devices as Device[]).flatMap((device) => {
    const sends: Promise<void>[] = [];
    if (device.apns_token) {
      sends.push(sendAPNs(device.apns_token, device.environment, bundleID, "alert", {
        aps: {
          alert: { title: `${circle.name} is ready`, body: "You have ten minutes to share today’s blessing." },
          sound: "default",
          "thread-id": prompt.circle_id,
          "interruption-level": "time-sensitive",
        },
        route: "blessingcircle://today/capture",
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
              body: "You have ten minutes to share today’s blessing.",
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
  return results.length - failures.length;
}

Deno.serve(async (request) => {
  if (request.headers.get("x-dispatch-secret") !== dispatchSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  await admin.rpc("ensure_tomorrow_prompts");
  const { data, error } = await admin.rpc("claim_due_prompts", { p_limit: 100 });
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const outcomes = [];
  for (const prompt of (data ?? []) as Prompt[]) {
    try {
      const delivered = await dispatchPrompt(prompt);
      await admin.from("daily_prompts").update({ state: "open", failure_reason: null }).eq("id", prompt.id);
      outcomes.push({ promptID: prompt.id, delivered });
    } catch (dispatchError) {
      const message = dispatchError instanceof Error ? dispatchError.message : String(dispatchError);
      await admin.from("daily_prompts").update({ state: "failed", failure_reason: message.slice(0, 500) }).eq("id", prompt.id);
      outcomes.push({ promptID: prompt.id, error: message });
    }
  }

  await admin
    .from("daily_prompts")
    .update({ state: "closed", closed_at: new Date().toISOString() })
    .in("state", ["open", "dispatching"])
    .lte("ends_at", new Date().toISOString());

  return Response.json({ claimed: outcomes.length, outcomes });
});

