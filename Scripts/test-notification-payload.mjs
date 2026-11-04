import assert from "node:assert/strict";
import {circleActivityTitle,circleActivityBody,circleActivityIdentity,notificationMedia,promptReminder,reminderMedia} from "../supabase/functions/dispatch-prompts/notification-payload.ts";
const base = {senderName:"Ben",message:"Grateful for this PRIVATE_BELIEF",scripture:{bookName:"PRIVATE_BOOK",chapter:1,verseStart:1,verseEnd:2},captureMode:"video",thumbnailPath:"private/frame.jpg",photoPath:"private/photo.jpg"};
for (const unlocked of [true,false]) {
 const input = {...base,eventType:"blessing_shared",unlocked};
 const body = circleActivityBody(input);
 assert.equal(circleActivityTitle("blessing_shared","Friends"),"New blessing in Friends");
 assert.ok(body.includes("Ben"));
 if (unlocked) {
  assert.equal(body,"Ben - Grateful for this PRIVATE_BELIEF\nPRIVATE_BOOK 1:1–2");
  assert.deepEqual(notificationMedia(input),{bucket:"blessing-media",path:"private/frame.jpg"});
 } else {
  assert.equal(body,"Ben has shared a blessing. Share to see.");
  assert.ok(!body.includes("PRIVATE"));
  assert.equal(notificationMedia(input),null);
 }
 // Both audiences get the sender's profile photo, separate from blessing media.
 assert.deepEqual(circleActivityIdentity({eventType:input.eventType,senderID:"ben-id",senderName:"Ben",circleName:"Friends",senderAvatarURL:"https://example.invalid/avatar.jpg"}),
  {sender_id:"ben-id",sender_name:"Ben",circle_name:"Friends",sender_avatar_url:"https://example.invalid/avatar.jpg"});
}
const plain = {...base,eventType:"blessing_shared",unlocked:true,scripture:{bookName:null,chapter:null,verseStart:null,verseEnd:null}};
assert.equal(circleActivityBody(plain),"Ben - Grateful for this PRIVATE_BELIEF");
assert.deepEqual(notificationMedia({...plain,captureMode:"typed"}),{bucket:"blessing-media",path:"private/photo.jpg"});
assert.equal(notificationMedia({...plain,captureMode:"voice",photoPath:null}),null);
assert.equal(notificationMedia({...plain,captureMode:"video",thumbnailPath:null,photoPath:null}),null);
assert.deepEqual(circleActivityIdentity({eventType:"blessing_shared",senderID:"ben-id",senderName:"Ben",circleName:"Friends",senderAvatarURL:null}),{sender_id:"ben-id",sender_name:"Ben",circle_name:"Friends"});
for(const eventType of ["response_shared","member_nudged"]) {
 for(const unlocked of [true,false]) {
  const input={...base,eventType,unlocked};
  assert.equal(circleActivityTitle(eventType,"PRIVATE_CIRCLE"),"manna circle");
  assert.ok(!circleActivityBody(input).includes("PRIVATE"));
  assert.equal(notificationMedia(input),null);
  assert.deepEqual(circleActivityIdentity({eventType,senderID:"private",senderName:"private",circleName:"private",senderAvatarURL:"private"}),{});
 }
}
assert.equal(reminderMedia("private/circle.jpg"),null);
for(const kind of ["daily","end_of_day"]) {
 const reminder=promptReminder({kind,circleName:"PRIVATE_CIRCLE",responseWindowMinutes:10});
 assert.equal(reminder.alert.title,"manna circle");
 assert.ok(!JSON.stringify(reminder).includes("PRIVATE"));
 assert.equal(reminder.startsLiveActivity,kind==='daily');
}
console.log("Blessing identity and share-to-see preview contracts passed.");

// Muted circle activity still permits direct nudges; ordinary activity keeps
// the preference. The dispatcher only supplies active, non-sender members.
const {circleActivityMemberIDs} = await import("../supabase/functions/dispatch-prompts/notification-recipients.ts");
const members = [
 {user_id:"muted",notify_on_circle_activity:false},
 {user_id:"enabled",notify_on_circle_activity:true},
];
assert.deepEqual([...circleActivityMemberIDs("member_nudged",members)], ["muted","enabled"]);
for (const eventType of ["blessing_shared","response_shared"]) {
 assert.deepEqual([...circleActivityMemberIDs(eventType,members)], ["enabled"]);
}
assert.equal(circleActivityMemberIDs("member_nudged",[]).size,0);
console.log("Nudges bypass circle activity preferences; blessing/response alerts retain them.");
