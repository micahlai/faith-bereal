#!/usr/bin/env node
// Operator-only tool. Credentials stay in child-process memory, never the report.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
const root = resolve(import.meta.dirname, '..');
const ref = readFileSync(resolve(root, 'supabase/.temp/project-ref'), 'utf8').trim();
if (ref !== 'lrdrodsgilmlzrynkiqx') throw Error('Unexpected project; stopping.');
const [action = 'list', id, choice] = process.argv.slice(2);
if (!['list', 'report', 'media'].includes(action)) throw Error('Use list | report UUID dismiss/hide/suspend | media UUID approve/reject');
const keys = JSON.parse(execFileSync('npx', ['-y','supabase@2.122.0','projects','api-keys','--project-ref',ref,'--output','json','--reveal'], {cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']}));
const key = keys.find(k => k.name === 'service_role')?.api_key;
if (!key) throw Error('Service credential unavailable');
const base = `https://${ref}.supabase.co`;
async function rpc(name, body) {
 const result = await fetch(`${base}/rest/v1/rpc/${name}`, {method:'POST',headers:{apikey:key,authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify(body)});
 if (!result.ok) throw Error(`Review operation failed (${result.status})`);
 const text = await result.text(); return text ? JSON.parse(text) : null;
}
if (action !== 'list') {
 if (!/^[0-9a-f-]{36}$/i.test(id ?? '')) throw Error('A review UUID is required');
 if (action === 'report' && ['dismiss','hide','suspend'].includes(choice)) await rpc('resolve_content_report',{p_report:id,p_action:choice});
 else if (action === 'media' && ['approve','reject'].includes(choice)) await rpc('resolve_media_review',{p_review:id,p_approve:choice==='approve'});
 else throw Error('Invalid review action');
 console.log('Review action saved.');
} else {
 const sql = `select json_build_object('reports',coalesce((select json_agg(r) from (select q.*,b.body blessing_text,r.body response_text from public.moderation_inbox(25) q left join public.blessings b on b.id=q.blessing_id left join public.blessing_responses r on r.id=q.response_id) r),'[]'::json),'media',coalesce((select json_agg(m) from (select q.*,coalesce(b.body,r.body) content,b.photo_path,b.video_path,coalesce(b.audio_path,r.audio_path) audio_path from public.media_review_inbox(25) q left join public.blessings b on b.id=q.blessing_id left join public.blessing_responses r on r.id=q.response_id) m),'[]'::json)) as inbox;`;
 const result = JSON.parse(execFileSync('npx',['-y','supabase@2.122.0','db','query','--linked','--output','json',sql],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']}));
 const inbox = result?.rows?.[0]?.inbox ?? result[0]?.inbox;
 if (!inbox) throw Error('Unexpected inbox response');
 // Links are short-lived capabilities; HTML contains no administrative credentials.
 const escape = s => String(s ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
 let html = '<!doctype html><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>Private manna review</title><style>body{max-width:70ch;margin:3rem auto;font:18px system-ui;padding:1rem}article{border-top:1px solid #aaa;padding:2rem 0}img,video{max-width:100%;max-height:60vh}pre{white-space:pre-wrap}</style><h1>Private review inbox</h1><p>Review daily. Urgent reports: act within 24 hours. Links expire in 10 minutes. Delete this local report after reviewing.</p>';
 for (const [kind, entries] of Object.entries(inbox)) for (const item of entries) {
  html += `<article><h2>${escape(kind)} ${escape(item.id)}</h2><pre>${escape(JSON.stringify(item,null,2))}</pre>`;
  for (const [field,tag] of [['photo_path','img'],['audio_path','audio'],['video_path','video']]) if (item[field]) {
   const path = item[field].split('/').map(encodeURIComponent).join('/');
   const response = await fetch(`${base}/storage/v1/object/sign/blessing-media/${path}`,{method:'POST',headers:{authorization:`Bearer ${key}`,'content-type':'application/json'},body:JSON.stringify({expiresIn:600})});
   if (!response.ok) throw Error('Could not prepare private review media');
   const data = await response.json(); const url = `${base}/storage/v1${data.signedURL}`;
   html += tag==='img' ? `<img alt="Pending review photo" src="${escape(url)}">` : `<${tag} controls preload="none" src="${escape(url)}"></${tag}>`;
  }
  html += '</article>';
 }
 mkdirSync(resolve(root,'build'),{recursive:true}); const file=resolve(root,'build/moderation-review.html');
 writeFileSync(file,html,{mode:0o600}); console.log(`Private inbox saved to ${file}`);
 console.log(`Reports: ${inbox.reports.length}; pending media: ${inbox.media.length}`);
}
