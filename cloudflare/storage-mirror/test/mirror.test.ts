import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { build } from 'esbuild';


const job = {
  job_id: '00000000-0000-4000-8000-000000000001',
  lease_token: '00000000-0000-4000-8000-000000000002',
  operation: 'copy', bucket_id: 'avatars', object_name: 'user/avatar.jpg',
  r2_key: 'v1/00000000-0000-4000-8000-000000000001',
};
let mf: Miniflare;
let bucket: R2Bucket;
let jobs: unknown[] = [];
let sourceStatus = 200;
let accepted: boolean | 'fail' = true;
let transportFailure = false;
let sourceLength = '19';
let calls: { url: string; args: any; init: any }[] = [];
before(async () => {
  const bundled = await build({ entryPoints: ['test/entry.ts'], bundle: true, write: false, format: 'esm' });
  mf = new Miniflare(convertV4MiniflareOptions({ modules: true, script: bundled.outputFiles[0].text,
    compatibilityDate: '2026-11-01', r2Buckets: ['MEDIA_MIRROR'],
    bindings: { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'test-server-only-key', MIRROR_ENABLED: 'true' },
    outboundService: async (request) => {
      const target = request.url;
      calls.push({ url: target, args: request.method === 'POST' ? await request.json() : null,
        init: { redirect: request.redirect, headers: Object.fromEntries(request.headers) } });
      if (target.endsWith('/functions/v1/account-lifecycle')) return Response.json({processed:0,completed:0});
      if (target.endsWith('claim_storage_mirror_jobs')) return Response.json(jobs);
      if (target.endsWith('finish_storage_mirror_job')) return accepted === 'fail'
        ? new Response('secret content', { status: 500 }) : Response.json(accepted);
      if (transportFailure) return new Response('unavailable', { status: 502 });
      return new Response('private-photo-bytes', { status: sourceStatus,
        headers: { 'content-length': sourceLength, 'content-type': 'image/jpeg', location: 'https://elsewhere.example/private' } });
    },
  }));
  bucket = await mf.getR2Bucket('MEDIA_MIRROR') as unknown as R2Bucket;
});
after(async () => { await mf.dispose(); });
function mock(nextJobs: unknown[], status = 200, ack = true) {
  jobs = nextJobs; sourceStatus = status; accepted = ack; transportFailure = false; sourceLength = '19'; calls = [];
  return calls;
}
async function run(overrides = {}) {
  const response = await mf.dispatchFetch('http://test/run', { method: 'POST', body: JSON.stringify(overrides) });
  if (!response.ok) throw new Error(await response.text());
}

test('copies original bytes to private native R2 and acknowledges', async () => {
  const calls = mock([job]);
  await run();
  assert.equal(await (await bucket.get(job.r2_key))?.text(), 'private-photo-bytes');
  assert.equal((await bucket.head(job.r2_key))?.httpMetadata?.cacheControl, 'private, no-store');
  assert.equal(calls.at(-1)?.args.p_error, null);
  assert.equal(calls[1].url, 'https://example.supabase.co/storage/v1/object/authenticated/avatars/user/avatar.jpg');
  assert.equal((calls[1].init.headers as any).authorization, 'Bearer test-server-only-key');
});

test('lost acknowledgement retries without downloading or overwriting existing copy', async () => {
  const calls = mock([job]);
  await run();
  assert.equal(calls.length, 2);
  assert.equal(calls.at(-1)?.args.p_error, null);
});

test('replacement uses an independent key and stale ACK leaves durable cleanup', async () => {
  const newer = { ...job, job_id: '00000000-0000-4000-8000-000000000003',
    r2_key: 'v1/00000000-0000-4000-8000-000000000003' };
  const calls = mock([newer], 200, false);
  await run();
  assert.equal(await (await bucket.get(job.r2_key))?.text(), 'private-photo-bytes');
  assert.equal(await (await bucket.get(newer.r2_key))?.text(), 'private-photo-bytes');
  assert.equal(calls.at(-1)?.args.p_job_id, newer.job_id);
});

test('idempotent deletion removes only the retired generation', async () => {
  const calls = mock([{ ...job, operation: 'delete' }]);
  await run();
  assert.equal(await bucket.head(job.r2_key), null);
  assert.ok(await bucket.head('v1/00000000-0000-4000-8000-000000000003'));
  await run();
  assert.equal(calls.at(-1)?.args.p_error, null);
  assert.ok(calls.every(c => !c.url.includes('/storage/')));
});

test('source failure records a sanitized retry and does not upload error body', async () => {
  const calls = mock([job], 503);
  await run();
  assert.equal(calls.at(-1)?.args.p_error, 'source');
  assert.equal(await bucket.head(job.r2_key), null);
});

test('source transport failure stays retryable without recording sensitive response', async () => {
  const calls = mock([job]);
  transportFailure = true;
  await run();
  assert.equal(calls.at(-1)?.args.p_error, 'source');
  assert.ok(!JSON.stringify(calls.map(c => c.args)).includes('secret'));
});

test('redirected and oversized sources are rejected without forwarding credentials or saving bodies', async () => {
  let calls = mock([job], 302);
  await run();
  assert.equal(calls.at(-1)?.args.p_error, 'source');
  assert.ok(calls.every(c => c.url.startsWith('https://example.supabase.co/')));
  assert.equal(await bucket.head(job.r2_key), null);
  calls = mock([job]); sourceLength = String(513 * 1024 * 1024);
  await run();
  assert.equal(calls.at(-1)?.args.p_error, 'source');
  assert.equal(await bucket.head(job.r2_key), null);
});

test('foreign R2 object metadata fails safely without overwriting or claiming a copy', async () => {
  await bucket.put(job.r2_key, 'foreign', { customMetadata: { generation: 'another-job' } });
  const calls = mock([job]);
  await run();
  assert.equal(calls.at(-1)?.args.p_error, 'storage');
  assert.equal(await (await bucket.get(job.r2_key))?.text(), 'foreign');
  await bucket.delete(job.r2_key);
});

test('disable switch makes no external requests and HTTP offers no media access', async () => {
  const calls = mock([job]);
  await run({ MIRROR_ENABLED: 'false' });
  assert.equal(calls.length, 0);
  assert.equal((await mf.dispatchFetch('http://test/production')).status, 404);
});

test('rejects arbitrary origins, path traversal, oversized batches and foreign keys', async () => {
  await assert.rejects(run({ SUPABASE_URL: 'https://evil.example' }), /configuration/);
  for (const bad of [{ ...job, object_name: '../secret' }, { ...job, r2_key: 'another-object' },
    { ...job, bucket_id: 'other' }, { ...job, lease_token: null }]) {
    const calls = mock([bad]);
    await assert.rejects(run(), /claim response/);
    assert.equal(calls.length, 1);
  }
  mock(Array(6).fill(job));
  await assert.rejects(run(), /claim response/);
});

test('failed RPC acknowledgement throws without logging sensitive response text', async () => {
  mock([job]);
  accepted = 'fail';
  await assert.rejects(run(), { message: 'Mirror acknowledgement failed' });
});

test('account cleanup is opt-in, server authenticated and follows mirror processing', async () => {
 let observed = mock([]);
 let response = await mf.dispatchFetch('http://test/scheduled', {method:'POST',body:'{}'});
 assert.ok(response.ok); assert.equal(observed.length,1);
 observed = mock([]);
 response = await mf.dispatchFetch('http://test/scheduled', {method:'POST',body:JSON.stringify({ACCOUNT_DELETION_ENABLED:'true',ACCOUNT_DELETION_PROCESSOR_SECRET:'test-server-only-key'})});
 assert.ok(response.ok); assert.equal(observed.length,2);
 assert.ok(observed[1].url.endsWith('/functions/v1/account-lifecycle'));
 assert.deepEqual(observed[1].args,{action:'process'});
 assert.equal(observed[1].init.headers.authorization,'Bearer test-server-only-key');
});
