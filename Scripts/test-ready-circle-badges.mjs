import assert from "node:assert/strict";
import {readyCircleBadgePayload,deliverReadyCircleBadges} from "../supabase/functions/dispatch-prompts/ready-circle-badges.ts";
assert.deepEqual(readyCircleBadgePayload(3),{aps:{badge:3}});
assert.deepEqual(readyCircleBadgePayload(0),{aps:{badge:0}});
for(const invalid of [-1,1.5,NaN,Infinity]) assert.throws(()=>readyCircleBadgePayload(invalid));
const claims=[0,1,2].map(i=>({device_id:`device-${i}`,apns_token:`private-${i}`,environment:"sandbox",badge_count:i,lease_token:`lease-${i}`}));
const acknowledgements=[], invalid=[];
const result=await deliverReadyCircleBadges(claims,{
 send:async(claim,payload)=>{assert.deepEqual(payload,{aps:{badge:claim.badge_count}});if(claim.badge_count===1)throw Error("invalid token");},
 complete:async(claim,success)=>{acknowledgements.push([claim.device_id,claim.lease_token,success]);if(claim.badge_count===2)throw Error("database retry");},
 invalidToken:async(claim,error)=>{assert.equal(error.message,"invalid token");invalid.push(claim.device_id);},
});
assert.deepEqual(result,{delivered:1,failed:2});
assert.equal(acknowledgements.length,3);
assert.deepEqual(acknowledgements.find(x=>x[0]==="device-1"),["device-1","lease-1",false]);
assert.deepEqual(invalid,["device-1"]);
console.log("Ready-circle badge payload, clear, failure isolation and acknowledgement checks passed.");
