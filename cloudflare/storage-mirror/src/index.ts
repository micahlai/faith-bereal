export interface Env {
  MEDIA_MIRROR: R2Bucket;
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  MIRROR_ENABLED: string;
  ACCOUNT_DELETION_ENABLED?: string;
  ACCOUNT_DELETION_PROCESSOR_SECRET?: string;
}

type Operation = 'copy' | 'delete';
interface Job {
  job_id: string;
  lease_token: string;
  operation: Operation;
  bucket_id: string;
  object_name: string;
  r2_key: string;
}
type Failure = 'source' | 'storage' | 'transport' | 'configuration';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const buckets = new Set(['blessing-media', 'avatars', 'circle-photos']);
const maxBytes = 512 * 1024 * 1024;

function origin(env: Env): string {
  const url = new URL(env.SUPABASE_URL);
  if (url.protocol !== 'https:' || !url.hostname.endsWith('.supabase.co') ||
      url.username || url.password || url.port || url.pathname !== '/' || url.search || url.hash ||
      !env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Mirror configuration invalid');
  return url.origin;
}

function validJob(value: unknown): value is Job {
  if (!value || typeof value !== 'object') return false;
  const j = value as Job;
  return typeof j.job_id === 'string' && uuid.test(j.job_id) &&
    typeof j.lease_token === 'string' && uuid.test(j.lease_token) &&
    (j.operation === 'copy' || j.operation === 'delete') && buckets.has(j.bucket_id) &&
    typeof j.object_name === 'string' && j.object_name.length <= 2048 &&
    j.object_name.split('/').every(p => p.length > 0 && p !== '.' && p !== '..' && !/[\\\u0000-\u001f]/.test(p)) &&
    j.r2_key === `v1/${j.job_id}`;
}

async function rpc(env: Env, name: string, args: object): Promise<unknown> {
  let response: Response;
  try {
    response = await fetch(`${origin(env)}/rest/v1/rpc/${name}`, {
      method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(15_000),
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify(args),
    });
  } catch { throw new Error('Mirror RPC transport failed'); }
  if (!response.ok) {
    await response.body?.cancel();
    throw new Error(`Mirror RPC HTTP ${response.status}`);
  }
  try { return await response.json(); } catch { throw new Error('Mirror RPC response invalid'); }
}

async function copy(env: Env, job: Job): Promise<Failure | null> {
  try {
    // A prior successful atomic PUT may have lost its acknowledgement. Reuse it
    // without downloading the original again. Each generation owns its own key.
    const existing = await env.MEDIA_MIRROR.head(job.r2_key);
    if (existing) return existing.customMetadata?.generation === job.job_id &&
      existing.customMetadata?.byteLength === String(existing.size) ? null : 'storage';
  } catch { return 'storage'; }
  const path = job.object_name.split('/').map(encodeURIComponent).join('/');
  let response: Response;
  try {
    response = await fetch(`${origin(env)}/storage/v1/object/authenticated/${job.bucket_id}/${path}`, {
      redirect: 'manual', signal: AbortSignal.timeout(90_000),
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'accept-encoding': 'identity' },
    });
  } catch { return 'transport'; }
  const length = Number(response.headers.get('content-length'));
  if (response.status !== 200 || !response.body || !response.headers.has('content-length') ||
      !Number.isSafeInteger(length) || length < 0 || length > maxBytes) {
    await response.body?.cancel();
    return 'source';
  }
  try {
    const stored = await env.MEDIA_MIRROR.put(job.r2_key, response.body, {
      httpMetadata: { contentType: response.headers.get('content-type') ?? 'application/octet-stream',
        cacheControl: 'private, no-store' },
      customMetadata: { generation: job.job_id, byteLength: String(length) },
      onlyIf: new Headers({ 'If-None-Match': '*' }),
    });
    if (!stored) {
      const existing = await env.MEDIA_MIRROR.head(job.r2_key);
      return existing?.customMetadata?.generation === job.job_id &&
        existing.size === length && existing.customMetadata?.byteLength === String(length) ? null : 'storage';
    }
    return stored && stored.size === length ? null : 'storage';
  } catch {
    await response.body.cancel().catch(() => {});
    return 'storage';
  }
}

async function processJob(env: Env, job: Job): Promise<void> {
  let error: Failure | null = null;
  if (job.operation === 'copy') error = await copy(env, job);
  else {
    try { await env.MEDIA_MIRROR.delete(job.r2_key); } catch { error = 'storage'; }
  }
  const accepted = await rpc(env, 'finish_storage_mirror_job', {
    p_job_id: job.job_id, p_lease_token: job.lease_token, p_operation: job.operation, p_error: error,
  });
  if (accepted !== true && accepted !== false) throw new Error('Mirror acknowledgement invalid');
  // False means an expired/fenced lease. Leave recovery to the durable queue.
}

export async function runMirror(env: Env): Promise<void> {
  if (env.MIRROR_ENABLED !== 'true') return;
  origin(env);
  const jobs = await rpc(env, 'claim_storage_mirror_jobs', { p_limit: 5 });
  if (!Array.isArray(jobs) || jobs.length > 5 || !jobs.every(validJob)) {
    throw new Error('Mirror claim response invalid');
  }
  // All claims begin promptly within this scheduled invocation. The database's
  // 20-minute leases / 30-minute retirement grace exceed its 15-minute lifetime.
  const results = await Promise.allSettled(jobs.map(job => processJob(env, job)));
  if (results.some(result => result.status === 'rejected')) throw new Error('Mirror acknowledgement failed');
}

export default {
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    await runMirror(env);
    if (env.ACCOUNT_DELETION_ENABLED === 'true') {
      if (!env.ACCOUNT_DELETION_PROCESSOR_SECRET) throw new Error('Account cleanup configuration missing');
      const response = await fetch(`${origin(env)}/functions/v1/account-lifecycle`, {
        method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(90_000),
        headers: { authorization: `Bearer ${env.ACCOUNT_DELETION_PROCESSOR_SECRET}`, 'content-type': 'application/json' },
        body: JSON.stringify({ action: 'process' }),
      });
      if (!response.ok) { await response.body?.cancel(); throw new Error('Account cleanup failed'); }
      const result = await response.json() as { failed?: number };
      if (result.failed) throw new Error("Some account cleanup jobs need retry");
    }
  },
  // Never expose an upload proxy, media reader, or administrative HTTP route.
  async fetch(): Promise<Response> { return new Response('Not found', { status: 404 }); },
} satisfies ExportedHandler<Env>;
