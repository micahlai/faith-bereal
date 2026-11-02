import { handler } from './index.ts';
const assert = (value: unknown, label: string) => { if(!value) throw Error(label); };
const service='fixture-service-key';const origin='https://fixture.supabase.co';
Deno.env.set('ACCOUNT_DELETION_PROCESSOR_SECRET',service);Deno.env.set('SUPABASE_URL',origin);Deno.env.set('SUPABASE_SERVICE_ROLE_KEY',service);
Deno.test('anonymous, wrong method and unprivileged processor are denied',async()=>{
 assert((await handler(new Request(origin,{method:'POST',body:'{}'}))).status===401,'anonymous');
 assert((await handler(new Request(origin))).status===405,'method');
 assert((await handler(new Request(origin,{method:'POST',headers:{authorization:'Bearer member'},body:'{"action":"process"}'}))).status===403,'processor');
});
Deno.test('receipt status uses a digest and reveals no account data',async()=>{
 const old=globalThis.fetch;let sent:Record<string,unknown>|undefined;
 globalThis.fetch=async(input,init)=>{
  assert(String(input).endsWith('/rpc/account_deletion_receipt_status'),'unexpected request');
  sent=JSON.parse(String(init?.body));return Response.json('completed');
 };
 try {
  const r=await handler(new Request(origin,{method:'POST',headers:{authorization:'Bearer anonymous-key'},body:JSON.stringify({action:'receipt',receipt:'a'.repeat(64)})}));
  assert(r.status===200,'receipt response');assert((await r.json()).status==='completed','status');
  assert(sent?.p_hash!=='a'.repeat(64)&&String(sent?.p_hash).length===64,'plaintext receipt leaked');
 }finally{globalThis.fetch=old;}
});
Deno.test('processor cannot finalize while mirror cleanup remains pending',async()=>{
 const old=globalThis.fetch;const calls:string[]=[];
 globalThis.fetch=async(input)=>{
  const path=new URL(input instanceof Request?input.url:String(input)).pathname;calls.push(path);
  if(path.endsWith('pending_account_deletions'))return Response.json([{user_id:'00000000-0000-4000-8000-000000000001'}]);
  if(path.endsWith('account_deletion_files'))return Response.json([]);
  if(path.endsWith('verify_account_deletion_cleanup'))return Response.json(false);
  if(path==='/auth/v1/admin/users/00000000-0000-4000-8000-000000000001')return Response.json({id:'00000000-0000-4000-8000-000000000001',aud:'authenticated',email:'fixture@example.invalid'});
  throw Error('Forbidden premature step');
 };
 try{
  const r=await handler(new Request(origin,{method:'POST',headers:{authorization:`Bearer ${service}`},body:'{"action":"process"}'}));
  assert(r.status===200,'processor request');assert((await r.json()).completed===0,'premature completion');
  assert(!calls.some(p=>p.endsWith('finish_account_deletion_receipt')),'premature receipt');
 }finally{globalThis.fetch=old;}
});
Deno.test('invalid receipt cannot call the database',async()=>{
 const old=globalThis.fetch;globalThis.fetch=()=>{throw Error('Unexpected network')};
 try{const r=await handler(new Request(origin,{method:'POST',headers:{authorization:'Bearer anon'},body:'{"action":"receipt","receipt":"guess"}'}));assert(r.status===400,'invalid receipt');}
 finally{globalThis.fetch=old;}
});
