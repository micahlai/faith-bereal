import { readFileSync } from 'node:fs';
import assert from "node:assert/strict";
import {circleActivityTitle,circleActivityBody,notificationMedia,promptReminder,reminderMedia} from "../supabase/functions/dispatch-prompts/notification-payload.ts";
for(const eventType of ["blessing_shared","response_shared","member_nudged"]) {
 for(const unlocked of [true,false]) {
  const input={eventType,unlocked,senderName:"PRIVATE_NAME",message:"PRIVATE_BELIEF",scripture:{bookName:"PRIVATE_BOOK",chapter:1,verseStart:1,verseEnd:1},captureMode:"video",thumbnailPath:"private/frame.jpg",photoPath:"private/photo.jpg"};
  const title=circleActivityTitle(eventType,"PRIVATE_CIRCLE");
  const body=circleActivityBody(input);
  assert.equal(title,"manna circle");
  assert.ok(!JSON.stringify({title,body}).includes("PRIVATE"));
  assert.equal(notificationMedia(input),null);
 }
}
assert.equal(reminderMedia("private/circle.jpg"),null);
for(const kind of ["daily","end_of_day"]) {
 const reminder=promptReminder({kind,circleName:"PRIVATE_CIRCLE",responseWindowMinutes:10});
 assert.equal(reminder.alert.title,"manna circle");
 assert.ok(!JSON.stringify(reminder).includes("PRIVATE"));
 assert.equal(reminder.startsLiveActivity,kind==='daily');
}
console.log("Generic private notification contract passed.");

// Notification service extensions can reveal custom identity fields even when
// aps.alert is generic. Keep those fields out of the server envelope entirely.
const dispatchSource = readFileSync(new URL('../supabase/functions/dispatch-prompts/index.ts',import.meta.url),'utf8');
for (const key of ['sender_name:', 'sender_avatar_url:', 'circle_name:', 'sender_id:']) {
 assert.ok(!dispatchSource.includes(key), `Private identity leaked through ${key}`);
}
