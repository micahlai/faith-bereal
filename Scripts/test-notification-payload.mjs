import assert from "node:assert/strict";
import {
  circleActivityBody,
  notificationMedia,
  scriptureReference,
} from "../supabase/functions/dispatch-prompts/notification-payload.ts";

const john316 = {
  bookName: "John",
  chapter: 3,
  verseStart: 16,
  verseEnd: 16,
};

assert.equal(scriptureReference(john316), "John 3:16");
assert.equal(scriptureReference({ ...john316, verseEnd: 18 }), "John 3:16–18");
assert.equal(
  circleActivityBody({
    eventType: "blessing_shared",
    senderName: "Micah",
    message: "A quiet morning",
    unlocked: true,
    scripture: john316,
  }),
  "Micah - A quiet morning\nJohn 3:16",
);
assert.equal(
  circleActivityBody({
    eventType: "blessing_shared",
    senderName: "Micah",
    message: "Private until sharing",
    unlocked: false,
    scripture: john316,
  }),
  "Micah has shared a blessing. share yours to see",
);
assert.equal(
  circleActivityBody({
    eventType: "response_shared",
    senderName: "Avery",
    message: "Amen",
    unlocked: true,
    scripture: john316,
  }),
  "Avery - Amen",
);

const mediaBase = {
  eventType: "blessing_shared",
  unlocked: true,
  captureMode: "video",
  thumbnailPath: "circle/prompt/user/thumbnail.jpg",
  photoPath: "circle/prompt/user/photo.jpg",
  senderAvatarPath: "user/avatar.jpg",
};
assert.deepEqual(notificationMedia(mediaBase), {
  bucket: "blessing-media",
  path: mediaBase.thumbnailPath,
});
assert.deepEqual(notificationMedia({ ...mediaBase, captureMode: "typed", thumbnailPath: null }), {
  bucket: "blessing-media",
  path: mediaBase.photoPath,
});
assert.deepEqual(notificationMedia({
  ...mediaBase,
  eventType: "response_shared",
  thumbnailPath: null,
  photoPath: null,
}), {
  bucket: "avatars",
  path: mediaBase.senderAvatarPath,
});
assert.equal(notificationMedia({ ...mediaBase, unlocked: false }), null);

console.log("APNs circle activity payload contract passed.");
