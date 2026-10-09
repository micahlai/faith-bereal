import assert from "node:assert/strict";
import {
  circleActivityBody,
  circleActivityTitle,
  notificationMedia,
  promptReminder,
  reminderMedia,
  scriptureReference,
} from "../supabase/functions/dispatch-prompts/notification-payload.ts";

const john316 = {
  bookName: "John",
  chapter: 3,
  verseStart: 16,
  verseEnd: 16,
};

assert.equal(reminderMedia(null), null);
assert.equal(reminderMedia(""), null);
assert.equal(reminderMedia("   "), null);
assert.deepEqual(reminderMedia("circle/circle.jpg"), {
  bucket: "circle-photos", path: "circle/circle.jpg",
});

assert.equal(circleActivityTitle("blessing_shared", "Sunday Table"), "New blessing in Sunday Table");
assert.equal(circleActivityTitle("response_shared", "Sunday Table"), "Sunday Table");
assert.equal(circleActivityTitle("member_nudged", "Sunday Table"), "Sunday Table");
for (const [kind, label] of [["daily", "daily"], ["end_of_day", "end-of-day"]]) {
  assert.equal(circleActivityBody({eventType: "member_nudged", senderName: "Micah", message: "Private blessing",
    unlocked: false, scripture: john316, promptKind: kind}), `Micah nudged you to share your ${label} blessing.`);
  assert.equal(notificationMedia({eventType: "member_nudged", unlocked: true,
    captureMode: "video", thumbnailPath: "private/frame.jpg", photoPath: "private/photo.jpg"}), null);
}

assert.deepEqual(promptReminder({
  kind: "end_of_day", circleName: "Evening Bread", responseWindowMinutes: 300,
}), {
  alert: { title: "Evening Bread", body: "What blessed you at the end of today?" },
  startsLiveActivity: false,
});
assert.deepEqual(promptReminder({
  kind: "daily", circleName: "Sunday Table", responseWindowMinutes: 10,
}), {
  alert: { title: "Sunday Table is ready", body: "You have 10 minutes to share today’s blessing." },
  startsLiveActivity: true,
});

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
};
assert.deepEqual(notificationMedia(mediaBase), {
  bucket: "blessing-media",
  path: mediaBase.thumbnailPath,
});
assert.deepEqual(notificationMedia({ ...mediaBase, captureMode: "typed", thumbnailPath: null }), {
  bucket: "blessing-media",
  path: mediaBase.photoPath,
});
assert.equal(notificationMedia({
  ...mediaBase,
  eventType: "response_shared",
  thumbnailPath: null,
  photoPath: null,
}), null);
assert.equal(notificationMedia({ ...mediaBase, captureMode: "voice", photoPath: null }), null);
assert.equal(notificationMedia({ ...mediaBase, captureMode: "typed", photoPath: null }), null);
assert.equal(notificationMedia({ ...mediaBase, unlocked: false }), null);

console.log("APNs circle activity payload contract passed.");
