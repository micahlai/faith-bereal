export type CircleActivityEvent = "blessing_shared" | "response_shared" | "member_nudged";

export function circleActivityTitle(eventType: CircleActivityEvent, circleName: string): string {
  return "manna circle";
}

export function promptReminder(input: {
  kind: "daily" | "end_of_day";
  circleName: string;
  responseWindowMinutes: number;
}): { alert: { title: string; body: string }; startsLiveActivity: boolean } {
  if (input.kind === "end_of_day") {
    return {
      alert: { title: "manna circle", body: "What blessed you at the end of today?" },
      startsLiveActivity: false,
    };
  }
  const windowLabel = input.responseWindowMinutes === 1
    ? "one minute"
    : `${input.responseWindowMinutes} minutes`;
  return {
    alert: {
      title: "manna circle",
      body: `You have ${windowLabel} to share today’s blessing.`,
    },
    startsLiveActivity: true,
  };
}

export type ScriptureReferenceParts = {
  bookName: string | null;
  chapter: number | null;
  verseStart: number | null;
  verseEnd: number | null;
};

export type NotificationMedia = {
  bucket: "blessing-media" | "circle-photos";
  path: string;
};

export function reminderMedia(circlePhotoPath: string | null): NotificationMedia | null {
  return null;
}

export function scriptureReference(parts: ScriptureReferenceParts): string | null {
  if (!parts.bookName || parts.chapter === null || parts.verseStart === null || parts.verseEnd === null) {
    return null;
  }
  const verses = parts.verseStart === parts.verseEnd
    ? `${parts.verseStart}`
    : `${parts.verseStart}–${parts.verseEnd}`;
  return `${parts.bookName} ${parts.chapter}:${verses}`;
}

export function circleActivityBody(input: {
  eventType: CircleActivityEvent;
  senderName: string;
  message: string;
  unlocked: boolean;
  scripture: ScriptureReferenceParts;
  promptKind?: "daily" | "end_of_day";
}): string {
  if (input.eventType === "member_nudged") return "Your circle invited you to share. Open manna to view.";
  if (input.eventType === "response_shared") return "There is a new response in your circle. Open manna to view.";
  return "There is a new blessing in your circle. Open manna to view.";
}

export function notificationMedia(input: {
  eventType: CircleActivityEvent;
  unlocked: boolean;
  captureMode: string;
  thumbnailPath: string | null;
  photoPath: string | null;
}): NotificationMedia | null {
  return null;
}
