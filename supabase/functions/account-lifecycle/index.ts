import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import { createRemoteJWKSet, jwtVerify, importPKCS8, SignJWT } from 'https://esm.sh/jose@6.1.0';
const appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
const json = (value: unknown,status=200) => new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
export const handler = async (request: Request) => {
 if(request.method!=='POST') return json({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL')!;const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
 const bearer=request.headers.get('authorization')?.replace(/^Bearer /,'');
 if(!bearer) return json({error:'Authentication required'},401);
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 try {
  const body=await request.json();
  if(body.action==='receipt') {
   if(typeof body.receipt!=='string'||! /^[a-fA-F0-9]{64}$/.test(body.receipt))return json({error:'Invalid receipt'},400);
   const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(body.receipt)))).map(b=>b.toString(16).padStart(2,'0')).join('');
   const {data,error}=await admin.rpc('account_deletion_receipt_status',{p_hash:hash});if(error)throw Error('database');
   return json({status:data});
  }
  if(body.action==='process') {
   if(!Deno.env.get('ACCOUNT_DELETION_PROCESSOR_SECRET')||bearer!==Deno.env.get('ACCOUNT_DELETION_PROCESSOR_SECRET')) return json({error:'Forbidden'},403);
   const {data:jobs,error}=await admin.rpc('pending_account_deletions',{p_limit:5});if(error)throw Error('database');
   let completed=0,failed=0;
   for(const job of jobs??[]) {
    try {
    const {data:files,error:filesError}=await admin.rpc('account_deletion_files',{p_user:job.user_id,p_limit:100});if(filesError)throw Error('database');
    for(const bucket of ['avatars','blessing-media','circle-photos']) {
     const names=(files??[]).filter((f: {bucket_id:string})=>f.bucket_id===bucket).map((f:{object_name:string})=>f.object_name);
     if(names.length){const {error:removeError}=await admin.storage.from(bucket).remove(names);if(removeError)throw Error('storage');}
    }
    const {data:ready,error:readyError}=await admin.rpc('verify_account_deletion_cleanup',{p_user:job.user_id});if(readyError)throw Error('database');
    const {data:existing}=await admin.auth.admin.getUserById(job.user_id);
    if(ready||!existing.user){
     if(existing.user){const {error:deleteError}=await admin.auth.admin.deleteUser(job.user_id);if(deleteError)throw Error('auth');}
     const {error:receiptError}=await admin.rpc('finish_account_deletion_receipt',{p_user:job.user_id});if(receiptError)throw Error('database');completed++;
    }
    } catch { failed++; }
   }
   return json({processed:jobs?.length??0,completed,failed});
  }
  const {data:{user},error:userError}=await admin.auth.getUser(bearer);
  if(userError||!user)return json({error:'Authentication required'},401);
  if(body.action==='status') {
   const {data,error}=await admin.rpc('account_deletion_requested',{p_user:user.id});if(error)throw Error('database');
   // Do not reveal another user's state.
   return json({status:data?'pending':'none'});
  }
  if(body.action!=='request'||typeof body.apple_code!=='string'||body.apple_code.length>4096) return json({error:'Invalid request'},400);
  let appleRevoked=false;
  const appleIdentity=user.identities?.find(i=>i.provider==='apple');
  if(appleIdentity){
   const clientID=Deno.env.get('APPLE_CLIENT_ID');let clientSecret=Deno.env.get('APPLE_CLIENT_SECRET');
   const privateKey=Deno.env.get('APPLE_PRIVATE_KEY'),keyID=Deno.env.get('APPLE_KEY_ID'),teamID=Deno.env.get('APPLE_TEAM_ID');
   if(clientID&&privateKey&&keyID&&teamID){
    const key=await importPKCS8(privateKey.replaceAll('\\n','\n'),'ES256');
    clientSecret=await new SignJWT({}).setProtectedHeader({alg:'ES256',kid:keyID}).setIssuer(teamID).setSubject(clientID).setAudience('https://appleid.apple.com').setIssuedAt().setExpirationTime('5m').sign(key);
   }
   if(!clientID||!clientSecret)return json({error:'Account deletion is temporarily unavailable. Contact support; your account has not been deleted.'},503);
   const response=await fetch('https://appleid.apple.com/auth/token',{method:'POST',body:new URLSearchParams({client_id:clientID,client_secret:clientSecret,code:body.apple_code,grant_type:'authorization_code'}),signal:AbortSignal.timeout(15000)});
   if(!response.ok)throw Error('apple');const tokens=await response.json();
   const {payload}=await jwtVerify(tokens.id_token,appleKeys,{issuer:'https://appleid.apple.com',audience:clientID});
   const expected=appleIdentity.identity_data?.sub??appleIdentity.id;
   if(payload.sub!==expected)return json({error:'Sign in with the Apple account you use for manna.'},403);
   if(!tokens.refresh_token)throw Error('apple');
   const revoked=await fetch('https://appleid.apple.com/auth/revoke',{method:'POST',body:new URLSearchParams({client_id:clientID,client_secret:clientSecret,token:tokens.refresh_token,token_type_hint:'refresh_token'}),signal:AbortSignal.timeout(15000)});
   if(!revoked.ok)throw Error('apple');appleRevoked=true;
  } else {
   // Non-Apple accounts are used only by isolated acceptance fixtures. Require a
   // recent authenticated session; production has no alternative signup flow.
   if(!user.last_sign_in_at||Date.now()-Date.parse(user.last_sign_in_at)>300000)return json({error:'Sign in again before deleting your account.'},401);
   appleRevoked=true;
  }
  if(typeof body.receipt!=='string'||! /^[a-fA-F0-9]{64}$/.test(body.receipt))return json({error:'Invalid receipt'},400);
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(body.receipt)))).map(b=>b.toString(16).padStart(2,'0')).join('');
  const {error}=await admin.rpc('request_account_deletion',{p_user:user.id,p_apple_revoked:appleRevoked,p_receipt_hash:hash});if(error)throw Error('database');
  return json({status:'pending',message:'Deletion is queued. Active access is disabled. Media cleanup is verified across both stores before the account is removed.'},202);
 } catch(error){
  // Never log Apple codes, JWTs, provider responses, paths, or personal content.
  const category=error instanceof Error&&['apple','database','storage','auth'].includes(error.message)?error.message:'request';
  return json({error:'Could not complete this step. Try again or contact support.',category},503);
 }
};
if(import.meta.main)Deno.serve(handler);
