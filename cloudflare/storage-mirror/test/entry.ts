// Test-only HTTP entrypoint; never bundled into the deployed scheduled Worker.
import worker, { runMirror, type Env } from '../src/index';
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (new URL(request.url).pathname === '/production') return worker.fetch();
    const overrides = await request.json() as Partial<Env>;
    try { await runMirror({ ...env, ...overrides }); return new Response('ok'); }
    catch (error) { return new Response((error as Error).message, { status: 500 }); }
  },
};
