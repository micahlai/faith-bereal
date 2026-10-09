# Product specification

## Product promise

manna circle creates a small, shared interruption for gratitude. The experience should feel intimate and present—not optimized for likes, streak anxiety, or public reach.

The brand name is **manna**, the full product name is **manna circle**, and the fullest App Store name is **manna circle - daily blessings**.

## Audience

Small trusted groups: families, friends, faith groups, teams, and communities that want a lightweight daily gratitude practice.

## Core loop

1. A person signs in with Apple and creates or joins a circle with a short code.
2. The server chooses one random daily moment for the circle within its configured waking window.
3. At that moment, APNs alerts every member and starts a Live Activity for the owner-configured response duration.
4. A member opens the capture flow and shares one circle-specific blessing as typed text, speech-transcribed text with audio, or a short video with transcript. They may optionally tag a Bible passage.
5. After submitting, today's blessings from peers unlock. Prior days remain visible at all times.
6. When the window closes, members can no longer enter a new capture flow unless the owner allows late posts. A member who entered before the deadline may finish and submit afterward; the post remains attached to that prompt's original circle day and is visibly labeled late.
7. Members can respond to a blessing with text or transcribed voice audio.

## Functional requirements

### Identity

- Sign in with Apple is the production identity provider.
- A profile contains a display name, optional avatar, locale, time zone, and notification preferences.
- Account deletion removes profile data and schedules media deletion.

### Circles

- Creating a circle first collects its name, IANA time zone, random-time range, response duration, late-post policy, and repeat window; the circle is committed only after the owner reviews those settings.
- Create a circle and receive a human-readable, case-insensitive invite code. Sharing sends an HTTPS invitation at `manna-circle.micahlai.com/join/<code>` that opens the installed app through Universal Links and otherwise presents the website fallback. The owner can regenerate the code later; rotation immediately invalidates the previous link/code without changing current memberships.
- Join by code, leave, and view members. If an owner leaves, ownership passes to the longest-standing remaining member; leaving an owner-only circle deletes it.
- The circle owner can rotate the invite code and remove members.
- Invite codes survive relaunch and app updates. A member-authorized server lookup recovers the private code; account/circle-isolated client hints can backfill legacy hash-only circles only after server verification. Never rotate automatically. Unknown legacy hashes are not reversible: a valid existing join link or one explicit owner rotation is required.
- The circle owner can upload, replace, or remove a private circle photo. Circle and profile photos use a circular pinch-and-drag crop editor and are normalized to a square JPEG before upload. Members see the circle photo in the Circle-page identity position, replacing the seven-dot fallback. The global circle switcher presents circle names without group icons.
- The circle owner can explicitly transfer ownership to another current member. The server performs the transfer atomically and the former owner remains a member.
- The circle owner can rename the circle, select its IANA time zone, configure the daily random-time range, choose a response duration from `1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180` minutes, allow or disallow late posts, and choose an end-of-day time no earlier than the random range's end.
- The circle owner configures a repeat window in minutes. A member may reuse one of their own blessings from another circle only when the target circle's current prompt is accepting submissions and the new submission occurs within that many minutes of the original blessing's `submitted_at` time. Notification and prompt start times do not affect repeat eligibility.
- Members can belong to multiple circles. A global top-bar menu switches the active circle, and all Today, Timeline, capture, response, and settings data follows that selection.

### User settings

- First launch is a reversible five-step flow: About, Appearance, App Icon, Local Saving, and Widget. Every step after the first provides Back and Continue controls. App-icon choices use the real cream and midnight artwork in equal one-column cards, and the widget page briefly explains both prompt and rotating-blessing states plus Apple's Home Screen installation steps. Accounts which completed the older setup are asked only for the new local-saving choice and widget reminder.
- A global hamburger menu opens user settings and circle management from every primary tab.
- Bible translation is an account-wide preference in user settings, not a circle setting.
- Appearance is an account-wide preference with system, light, and dark choices.
- Bible translations are grouped by language, with language groups ordered by broad usage and translations clearly labeled by language and abbreviation.
- User settings list every joined circle with separate switches for peer blessing/followed-response alerts and the end-of-day reminder. Both default on.

### Daily prompt

- One prompt per circle per local calendar day.
- Random start time is selected server-side within a circle-configured window, default 12:00–22:00, with late blessings enabled by default.
- Circle creation transactionally schedules the current local-day prompt from the owner's initial settings so the selected time range and response duration apply on day one. The join-day exception still lets the creator share at any time that local day.
- The preselected random time is the dispatch target. When the server claims that prompt, it authors the shared `starts_at` from the actual dispatch and sets `ends_at = starts_at + response_window_minutes`, giving every member the complete configured entry window.
- The response deadline controls entry into capture, not completion of a capture already opened. The server records an entry grant before presenting capture; that grant remains valid if composition or upload finishes after the deadline or after midnight.
- A notification and Live Activity deep-link to today's capture screen.
- Daily and end-of-day reminders show the circle's custom photo as an optional right-hand attachment; the default circle image is not attached. Peer blessing notifications retain attached-photo/video thumbnails.
- The lock-screen Live Activity shows the circle name, “What has blessed you today”, and a smaller live “`m:ss to respond`” countdown. After the viewer submits, it changes immediately to “Blessing submitted”. Dynamic Island presentation remains distinct and unchanged.
- After a member submits, the Live Activity remains visible for three minutes. Without late sharing it remains for three minutes after the entry deadline; with late sharing it stays available until that member submits or a newer circle prompt replaces it.

### End-of-day prompt

- Every circle has a second, independent end-of-day prompt, defaulting to 22:00 in the circle time zone and never scheduled before the daily random range ends.
- It sends one ordinary push notification to members who enabled that circle's end-of-day reminder. It never starts a Live Activity and Today presents no countdown.
- Entry opens at the configured time and closes after five hours or when the next daily random prompt starts, whichever happens first. A member who enters while open retains the same server entry grant as the daily capture flow and may finish afterward.
- Its privacy gate is independent: submitting the random daily blessing does not reveal peer end-of-day blessings, and vice versa.
- End-of-day blessings use the same capture, edit, scripture, media, response, and notification behavior as other blessings. Today mixes visible blessings by recency. Timeline renders the end-of-day event above the random event inside the same member/day cell.

### Capture

- Typed: multiline text, 1–1,200 characters, with an optional captured or uploaded photo. The same 1,200-character maximum applies to voice/video transcripts and edits; response text/transcripts remain limited to 600. Character counters match the database's Unicode-scalar length (combined emoji/accents can count as multiple characters), and capture truncation never splits a displayed grapheme.
- Voice: in-app live transcription that the user can edit before submission, with private audio playback in detail and an optional captured or uploaded photo.
- Video: camera capture with editable transcript and private playback.
- Optional scripture tag: book and chapter dropdowns, then a drag-select square verse grid. Preview in the user's chosen public-domain Bible translation before sending.
- Submission shows an explicit progress state and cannot be duplicated by repeated taps.
- The server is authoritative for membership, prompt state, entry deadline, entry grants, and uniqueness. A client cannot create a post-deadline grant by changing its clock.
- When eligible, capture offers a quiet “Reuse a recent blessing” action. It preserves the original capture format, message/transcript, Bible reference, and attached audio, photo, or video as a new blessing in the target circle. Hosted media references are reused without re-uploading; target-circle members can read them only through the target blessing's visibility gate. Responses are not copied. It never exposes unavailable or expired reuse choices.
- Voice capture records playable audio while producing an editable transcript. Capture previews and submitted voice content include play/pause, elapsed and total time, and a seekable playhead. Camera capture owns its recording lifecycle and handles authorization, interruption, denial, and unavailable hardware on physical devices.
- An author may edit the text or transcript and optional scripture tag for exactly ten minutes after `submitted_at`. The global limit is independent of circle settings, is enforced by the server, and never replaces the original audio, video, or photo.

### Circle activity notifications

- A new blessing notifies enabled members other than its author. Before the recipient shares for that prompt, the body is exactly “`[name] has shared a blessing. share yours to see`” and routes to Today; afterward it is “`[name] - [blessing text/transcript]`” and routes to the blessing. A tagged scripture reference appears on the next line without scripture text.
- A new response notifies the blessing author and members who responded earlier, excluding the new responder, using “`[name] - [response]`” and routing to the blessing.
- Blessing alert titles are “New blessing in [circle name]”; response alert titles are “[circle name]”. Message bodies and scripture-reference lines retain the rules above.
- Activity alerts use the author/responder's full profile photo as the primary left artwork, center-cropped to fill the identity image. The recipient's selected manna logo is a fallback only when the photo is missing or unavailable. iOS retains its separate app-icon badge at the lower right; apps cannot replace that system badge. The communication intent carries the circle-oriented alert title so iOS does not replace it with the author's name.
- The right rich-media thumbnail is an attached blessing photo or the video's first frame, never a profile photo. Text/voice blessings without a photo and all responses have no right attachment. Locked blessing alerts do not leak blessing content or media; the sender avatar is ordinary circle-member identity and can appear before unlocking. iOS controls exact compact-banner placement and truncation.
- Notification events are transactionally queued by the database and dispatched server-side. Clients cannot broadcast a fabricated blessing or response alert.

### Today

- Visible blessings offer Save blessing for a private device copy, separately from photo/video export to Photos.

- Before a prompt starts, Today shows the waiting state. During an open prompt, it shows the response timer and capture action until the viewer submits.
- After submission, Today becomes a vertically scrolling, full-width feed of every visible blessing for that circle's current prompt, including text/transcript, media preview or playback, optional full scripture passage, and responses.
- Each Today blessing uses one continuous panel for its content, scripture, response history, and composer. The blessing body and transcript are presented directly without redundant “Reflection,” “Transcript,” or “Responses” headings.
- Responses can be authored directly from Today. A current-day blessing opened from Timeline may also accept a response; historical Timeline details are read-only.

### Timeline

- A vertically scrollable timeline with a horizontal lane per member, each with a vertical thread. Profile photos and names sit in a compact fixed header directly below navigation; they move with horizontal member scrolling but stay pinned vertically.
- Dates are viewport-anchored to the left of a continuous vertical divider with eight points of trailing padding. A full-height opaque strip hides body content beneath them, including the leading gutter and during horizontal overscroll. The date strip begins below the header, so it never masks profile photos or names. Body content cannot paint above the header's horizontal divider.
- Each daily event has a dated dot, content preview, and time.
- A missed day has a distinct hollow marker and text label; color is never the only cue.
- Before the daily prompt starts, empty lanes say Waiting for notification, not You can still share or Missed; the first-day exception remains shareable. Future calendar-day prompts are omitted. Existing current-day peer blessings remain gated even when a member posted early under that exception.
- Past days are visible to members regardless of today's submission.
- Current-day peer content is replaced by a locked state until the viewer posts.
- Previews show up to 15 lines of original text or transcript plus the reference when present. Every member cell for a given day shares the height of that day's longest preview.
- Timeline blessing previews show only the profile icons of members who responded, without response text.
- Tapping a blessing opens text, audio plus transcript, or video plus transcript. Audio exposes a seekable playhead; video preserves its original presentation aspect ratio and uses Apple's native inline/full-screen playback controls. An optional photo appears with text or audio content, tagged scripture appears before responses in the viewer's selected translation, and historical responses are view-only; current-day details may include the response composer.
- Each member lane stops at a “Joined circle” marker and never fabricates missed days before membership began.

### Later scope: widgets

- A widget shows “Time to share blessings for [circle name]” while any joined circle has an active prompt and deep-links to Today.
- Outside share time, it rotates blessings across all joined circles at a user-configured interval, defaulting to 30 minutes.
- Widget content includes scripture when present and uses transcripts for voice/video blessings. It prioritizes current-day, recent, and not-yet-shown blessings; before any prompt has fired today, it falls back to the most recent prior-day blessing.
- Blessing widgets identify the member without a decorative capture/quotation glyph. In the compact 2×2 family, the circle name sits below the member name so both remain clear of the top-right manna logo.
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
- multiple posts per person per daily prompt;
- background speech recording.

## Private saves and media retention

- Audio/video blessings and audio responses expire on the server 30 days after each submission. Text, transcripts, Bible references, response records, and attached photos remain in history.
- Save blessing captures its available text/reference/media and current responses in private on-device storage scoped to the signed-in account. It neither changes other users' access nor extends server retention. New responses are not added automatically.
- Saved media opens from the existing Timeline card after hosted expiry. The first save explains device-only storage, snapshot behavior, and loss on uninstall/device loss. Photo/video export to Photos is independent.
- Above the Timeline card, show Saved for an archived blessing; otherwise show an audio/video expiry warning during the final 48 hours, including response audio due to expire. Text-only blessings with no voice responses do not get a false expiry warning.
- Unsave removes only this account's local copy. If captured media is already past its hosted expiry, require a permanent-loss confirmation first.
- Automatically save locally is an opt-in, account/device-specific setting offered during startup and in User settings. While the app is open, it archives visible blessings across all joined circles and refreshes automatic copies for new responses/edits. It does not unlock peer content or promise background downloads. Failures retry on the next refresh; they never interrupt scrolling with an alert.
- Turning automatic saving off pauses the worker while the user chooses Keep all, Keep only my blessings, Keep none, or Choose from a list. Retained automatic copies become ordinary manual saves; pre-existing manual saves are untouched. Removing captured expired audio/video requires a permanent-loss confirmation. Cancel leaves automatic saving enabled. Individual Unsave excludes that blessing from future automatic saves.
- See `docs/MEDIA_RETENTION.md` for storage, cleanup, and safe rollout details.

## Customer Help and circle setup

- Help is available from the hamburger menu both inside a circle and in the no-circle state. Illustrated, plain-language topics explain sharing, evening reflections, circles, Timeline, responses, saving/expiry, Bible tags, notifications/widgets, and personal settings. A Topics menu jumps between features without building a deep navigation stack.
- Every customer-visible feature change must update the matching Help topic and relevant tests.
- Creating a circle opens a full-screen guided page with progress and Back/Continue controls. Collect name, optional photo, time zone, random-time range, entry duration, late-sharing policy, end-of-day time, and repeat window one step at a time. Validate each relevant step; preserve selections on Back. A final review precedes the sole create action.

## Accessibility

- All common tasks use native named controls with 44-point minimum targets, Dynamic Type, adaptive colors, and explicit status text/symbols. Reduced Motion disables custom countdown/onboarding animations.
- Timeline offers Threads and a single-column List. List defaults on for VoiceOver and accessibility text sizes; it preserves membership boundaries, privacy gates, statuses, detail opening, and saved-media behavior. Spoken card names include author, circle-local date, prompt kind, capture mode, full text/transcript, late status, and Bible reference.
- Verse selection supports native Start/End steppers alongside the drag grid, with scaled cells and selected traits/borders. Photo cropping supports an Adjust photo menu and VoiceOver zoom/movement/reset actions alongside pinch/drag. All methods produce the same square upload.
- At accessibility sizes, countdown text is not constrained inside a fixed-size ring, and guided creation uses stacked navigation. Colors distinguish foreground tints from white-on-orange action fills; Increased Contrast strengthens card and divider boundaries.
- Help includes an Accessibility topic explaining these alternatives and current limitations. Audio/video transcripts are readable and author-editable. Timed video captions, author-provided image descriptions, and narrated visual-description tracks are not yet implemented; do not claim full Captions or Audio Descriptions support.
- Before declaring an App Store accessibility label, validate every common task on each supported device class. Automated audits and simulator checks do not replace physical VoiceOver, Voice Control, camera/media, and system-permission testing. See `docs/ACCESSIBILITY_AUDIT.md`.

## Success measures

- prompt-to-submission conversion;
- percent of posts submitted inside the configured window;
- notification-to-capture-open latency;
- weekly circle retention;
- failed upload and missed-push rates;
- account deletion completion time.

## Open product decisions

- Whether video originals should be downsampled after upload; audio/video retention is fixed at 30 days.
- Trademark and App Store availability checks for “manna circle - daily blessings” are required before release.
