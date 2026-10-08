export type CircleActivityEvent = "blessing_shared" | "response_shared";

export function circleActivityTitle(eventType: CircleActivityEvent, circleName: string): string {
  return eventType === "blessing_shared" ? `New blessing in ${circleName}` : circleName;
}

export function promptReminder(input: {
  kind: "daily" | "end_of_day";
  circleName: string;
  responseWindowMinutes: number;
}): { alert: { title: string; body: string }; startsLiveActivity: boolean } {
  if (input.kind === "end_of_day") {
    return {
      alert: { title: input.circleName, body: "What blessed you at the end of today?" },
      startsLiveActivity: false,
    };
  }
  const windowLabel = input.responseWindowMinutes === 1
    ? "one minute"
    : `${input.responseWindowMinutes} minutes`;
  return {
    alert: {
      title: `${input.circleName} is ready`,
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
  bucket: "blessing-media";
  path: string;
};

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
}): string {
  if (input.eventType === "blessing_shared" && !input.unlocked) {
    return `${input.senderName} has shared a blessing. share yours to see`;
  }
  const firstLine = `${input.senderName} - ${input.message}`;
  if (input.eventType === "response_shared") return firstLine;
  const reference = scriptureReference(input.scripture);
  return reference ? `${firstLine}\n${reference}` : firstLine;
}

export function notificationMedia(input: {
  eventType: CircleActivityEvent;
  unlocked: boolean;
  captureMode: string;
  thumbnailPath: string | null;
  photoPath: string | null;
}): NotificationMedia | null {
  if (!input.unlocked) return null;
  if (input.eventType === "blessing_shared") {
    if (input.captureMode === "video" && input.thumbnailPath) {
      return { bucket: "blessing-media", path: input.thumbnailPath };
    }
    if (input.photoPath) {
      return { bucket: "blessing-media", path: input.photoPath };
    }
  }
  return null;
}
