# Product specification

## Product promise

Blessing Circle creates a small, shared interruption for gratitude. The experience should feel intimate and present—not optimized for likes, streak anxiety, or public reach.

## Audience

Small trusted groups: families, friends, faith groups, teams, and communities that want a lightweight daily gratitude practice.

## Core loop

1. A person signs in with Apple and creates or joins a circle with a short code.
2. The server chooses one random daily moment for the circle within its configured waking window.
3. At that moment, APNs alerts every member and starts a Live Activity for the owner-configured response duration.
4. A member opens the capture flow and shares one circle-specific blessing as typed text, speech-transcribed text with audio, or a short video with transcript. They may optionally tag a Bible passage.
5. After submitting, today's blessings from peers unlock. Prior days remain visible at all times.
6. When the window closes, members without a post receive a missed marker in history. If the owner allows late posts, they remain accepted and visibly labeled until the next prompt.
7. Members can respond to a blessing with text or transcribed voice audio.

## Functional requirements

### Identity

- Sign in with Apple is the production identity provider.
- A profile contains a display name, optional avatar, locale, time zone, and notification preferences.
- Account deletion removes profile data and schedules media deletion.

### Circles

- Create a circle and receive a human-readable, case-insensitive invite code.
- Join by code, leave, and view members. If an owner leaves, ownership passes to the longest-standing remaining member; leaving an owner-only circle deletes it.
- The circle owner can rotate the invite code and remove members.
- The circle owner can explicitly transfer ownership to another current member. The server performs the transfer atomically and the former owner remains a member.
- The circle owner can rename the circle, select its IANA time zone, configure the daily random-time range, choose a response duration from `1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180` minutes, and allow or disallow late posts.
- The circle owner configures a repeat window in minutes. A member may reuse one of their own blessings from another circle only when the target circle's current prompt is accepting submissions and the new submission occurs within that many minutes of the original blessing's `submitted_at` time. Notification and prompt start times do not affect repeat eligibility.
- Members can belong to multiple circles. A global top-bar menu switches the active circle, and all Today, Timeline, capture, response, and settings data follows that selection.

### User settings

- A global hamburger menu opens user settings and circle management from every primary tab.
- Bible translation is an account-wide preference in user settings, not a circle setting.
- Appearance is an account-wide preference with system, light, and dark choices.
- Bible translations are grouped by language, with language groups ordered by broad usage and translations clearly labeled by language and abbreviation.

### Daily prompt

- One prompt per circle per local calendar day.
- Random start time is selected server-side within a circle-configured window, default 08:00–20:00.
- Start time is immutable after publication and identical for all circle members.
- Response deadline is `starts_at + response_window_minutes`; setting changes apply to future prompts.
- A notification and Live Activity deep-link to today's capture screen.

### Capture

- Typed: multiline text, 1–600 characters, with an optional captured or uploaded photo.
- Voice: in-app live transcription that the user can edit before submission, with private audio playback in detail and an optional captured or uploaded photo.
- Video: camera capture with editable transcript and private playback.
- Optional scripture tag: book and chapter dropdowns, then a drag-select square verse grid. Preview in the user's chosen public-domain Bible translation before sending.
- Submission shows an explicit progress state and cannot be duplicated by repeated taps.
- The server is authoritative for membership, prompt state, deadline, and uniqueness.
- When eligible, capture offers a quiet “Reuse a recent blessing” action. It copies the original message or transcript and optional scripture reference into the target circle as a new typed blessing; it never exposes unavailable or expired reuse choices.
- Voice capture records playable audio while producing an editable transcript. Camera capture owns its recording lifecycle and handles authorization, interruption, denial, and unavailable hardware on physical devices.

### Today

- Before a prompt starts, Today shows the waiting state. During an open prompt, it shows the response timer and capture action until the viewer submits.
- After submission, Today becomes a vertically scrolling, full-width feed of every visible blessing for that circle's current prompt, including text/transcript, media preview or playback, optional full scripture passage, and responses.
- Responses can be authored directly from Today. A current-day blessing opened from Timeline may also accept a response; historical Timeline details are read-only.

### Timeline

- A vertically scrollable timeline with a horizontal lane per member, each with a vertical thread. Profile photos and names stay pinned while the timeline scrolls vertically.
- Each daily event has a dated dot, content preview, and time.
- A missed day has a distinct hollow marker and text label; color is never the only cue.
- Past days are visible to members regardless of today's submission.
- Current-day peer content is replaced by a locked state until the viewer posts.
- Previews show up to 15 lines of original text or transcript plus the reference when present. Every member cell for a given day shares the height of that day's longest preview.
- Timeline blessing previews show only the profile icons of members who responded, without response text.
- Tapping a blessing opens text, audio plus transcript, or video plus transcript. An optional photo appears with text or audio content, tagged scripture appears before responses in the viewer's selected translation, and historical responses are view-only; current-day details may include the response composer.
- Each member lane stops at a “Joined circle” marker and never fabricates missed days before membership began.

### Later scope: widgets

- A widget shows “Time to share blessings for [circle name]” while any joined circle has an active prompt and deep-links to Today.
- Outside share time, it rotates blessings across all joined circles at a user-configured interval, defaulting to 30 minutes.
- Widget content includes scripture when present and uses transcripts for voice/video blessings. It prioritizes current-day, recent, and not-yet-shown blessings; before any prompt has fired today, it falls back to the most recent prior-day blessing.
- Tapping displayed content deep-links to the corresponding blessing detail.

## Visibility policy

For a member `viewer`, prompt `P`, and peer post `X`:

- if `P` is before today, `X` is visible;
- if `P` is today and `viewer` has a post for `P`, `X` is visible;
- if `P` is today and `viewer` has not posted, peer content is hidden, while status and the viewer's own draft remain visible;
- membership in the circle is required in all cases.

This resolves the example in the brief as “history is always readable; only the current day's peer content is gated.”

## Non-goals for MVP

- public discovery, follower counts, reactions, direct messages, rankings, and visible streak leaderboards;
- Android or web clients;
- content editing after submission;
- multiple posts per person per daily prompt;
- background speech recording.

## Success measures

- prompt-to-submission conversion;
- percent of posts submitted inside the configured window;
- notification-to-capture-open latency;
- weekly circle retention;
- failed upload and missed-push rates;
- account deletion completion time.

## Open product decisions

- Exact video retention policy and whether originals are downsampled after upload.
- Whether the name “Blessing Circle” is final; trademark and App Store naming checks are required.
