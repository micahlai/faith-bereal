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
- Create a circle and receive a human-readable, case-insensitive invite code. Sharing sends an HTTPS invitation at `manna-circle.micahlai.com/join/<code>` that opens the installed app through Universal Links and otherwise presents the website fallback. An authorized circle editor can regenerate the code later; rotation immediately invalidates the previous link/code without changing current memberships.
- Join by code, leave, and view members. If an owner leaves, ownership passes to the longest-standing remaining member; leaving an owner-only circle deletes it.
- Circle changes default to leader-only. The leader can enable Anyone can make circle changes, allowing current members to edit the circle name/photo/schedule/late/reuse settings, rotate invite codes, force a notification, and remove another nonleader member. Only the leader may change this permission or transfer ownership. Members cannot remove themselves through member management (use Leave circle) or remove the leader.
- Invite codes survive relaunch and app updates. A member-authorized server lookup recovers the private code; account/circle-isolated client hints can backfill legacy hash-only circles only after server verification. Never rotate automatically. Unknown legacy hashes are not reversible: a valid existing join link or one explicit owner rotation is required.
- An authorized circle editor can upload, replace, or remove a private circle photo. Circle and profile photos use a circular pinch-and-drag crop editor and are normalized to a square JPEG before upload. Members see the circle photo in the Circle-page identity position, replacing the seven-dot fallback. The global circle switcher presents circle names without group icons.
- The circle owner can explicitly transfer ownership to another current member. The server performs the transfer atomically and the former owner remains a member.
- An authorized circle editor can rename the circle, select its IANA time zone, configure the daily random-time range, choose a response duration from `1, 2, 3, 5, 10, 15, 20, 40, 60, 90, 120, 180` minutes, allow or disallow late posts, and choose an end-of-day time no earlier than the random range's end.
- An authorized circle editor configures a repeat window in minutes. A member may reuse one of their own blessings from another circle only when the target circle's current prompt is accepting submissions and the new submission occurs within that many minutes of the original blessing's `submitted_at` time. Notification and prompt start times do not affect repeat eligibility.
- Members can belong to multiple circles. A global top-bar menu switches the active circle, and all Today, Timeline, capture, response, and settings data follows that selection.
- Account-scoped display metadata (circle details, members, streaks, profile/circle photos) can appear immediately during startup and switching. Protected local metadata and bounded identity-photo bytes expire after seven days; sign-out removes the outgoing account cache. Cached invitations/permissions never authorize sharing or edits, and blessings/prompts/responses are not restored from this cache. Each page has an explicit loading/error indicator and Retry; tabs remain usable. Foreground refreshes coalesce, and optional widget/automatic-saving reads wait for visible loading to finish.
- A circle switch installs its fresh content only if the account and selected scope still match. An interrupted switch keeps the previous circle selected, restores live updates, and can be retried. Delayed Timeline pages and refresh errors cannot overwrite a newer account/circle/time-zone scope, even if the user later returns to its previous IDs.

### User settings

- Sign-in uses the manna wordmark. Sign out is located only in User settings, not the global menu or Circle page.

- First launch is a reversible six-step flow: About, Your Profile, Appearance, App Icon, Local Saving, and Widget. Every step after the first provides Back and Continue controls. App-icon choices use the real cream and midnight artwork in equal one-column cards, and the widget page briefly explains both prompt and rotating-blessing states plus Apple's Home Screen installation steps. Accounts which completed the older setup are asked only for the new local-saving choice and widget reminder.
- A global hamburger menu opens user settings and circle management from every primary tab.
- Bible translation is an account-wide preference in user settings, not a circle setting.
- Appearance is an account-wide preference with system, light, and dark choices.
- User settings offers optional Share diagnostic data for field testing, including TestFlight. This field-testing build defaults on for a new account/device; explicit choices and legacy saved off settings survive updates and relaunch. Settings disclose the default and allow disabling. It collects typed timing/size/outcome metrics, sanitized failure sources and short structured error codes, app build, and a random session code. Backend connection-limit classification and Speech/audio errors are included without transmitting their messages. Upload failures queue one record per distinct source/code/category until a successful send. Pending failures take priority over routine samples, while frozen retries remain exact; queue pressure discards routine records first. Reports are linked to the authenticated account and cannot be read by peers. No names, blessing content, media, paths/URLs, credentials, or error descriptions enter the payload. Bounded foreground batches retry idempotently with a protected device queue and 14-day server retention/periodic cleanup. Opt-out drops unsent records; an in-flight upload may finish. Local demo keeps records on-device. See `TESTFLIGHT_FIELD_TESTING.md` for limits/operator access.
- Bible translations are grouped by language, with language groups ordered by broad usage and translations clearly labeled by language and abbreviation.
- User settings list every joined circle with separate switches for peer blessing/followed-response alerts and the end-of-day reminder. Both default on.

### Daily prompt

- One prompt per circle per local calendar day.
- Random start time is selected server-side within a circle-configured window, default 12:00–22:00, with late blessings enabled by default.
- Circle creation transactionally schedules the current local-day prompt from the owner's initial settings. On the circle-local day a member joins, a welcome blessing belongs to yesterday until today's notification starts; afterward it belongs to today and entry is allowed until that day ends. An entry grant preserves that original date when sending later.
- The preselected random time is the dispatch target. When the server claims that prompt, it authors the shared `starts_at` from the actual dispatch and sets `ends_at = starts_at + response_window_minutes`, giving every member the complete configured entry window.
- A scheduled target passing does not itself open sharing or close welcome/evening entry. Hosted clients and authorization preserve scheduled state until the server starts that notification.
- The response deadline controls entry into capture, not completion of a capture already opened. The server records an entry grant before presenting capture; that grant remains valid if composition or upload finishes after the deadline or after midnight.
- A notification and Live Activity deep-link to today's capture screen.
- Daily and end-of-day reminders show the circle's custom photo as an optional right-hand attachment; the default circle image is not attached. Peer blessing notifications retain attached-photo/video thumbnails.
- The lock-screen Live Activity shows the circle name, “What has blessed you today”, and a smaller live “`m:ss to respond`” countdown. After the viewer submits, it changes immediately to “Blessing submitted”. Dynamic Island presentation remains distinct and unchanged.
- After a member submits, the Live Activity remains visible for three minutes. Without late sharing it remains for three minutes after the entry deadline. Late sharing ends at the circle's next midnight (or the regular deadline if that is later); the server ends the activity with the same three-minute grace period. A stale activity never grants entry to a closed past day. The Dynamic Island layout is unchanged.

### End-of-day prompt

- Every circle has a second, independent end-of-day prompt, defaulting to 22:00 in the circle time zone and never scheduled before the daily random range ends.
- It sends one ordinary push notification to members who enabled that circle's end-of-day reminder. It never starts a Live Activity and Today presents no countdown.
- Entry opens at the configured time and closes after seven hours or when the next daily random prompt starts, whichever happens first. A member who enters while open retains the same server entry grant as the daily capture flow and may finish afterward.
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
- Voice recording keeps the screen awake only while actively recording; pause, stop, interruption, backgrounding, or leaving capture restores normal sleep behavior. Blessing and response recorders share this ownership rule.
- In-progress blessings checkpoint text, scripture, capture mode, and local media privately on this device, isolated by account, circle, and prompt. The ordinary daily or end-of-day sharing action on Today changes to Continue for its own eligible saved draft, restoring unsent changes without a separate draft button. Successful submission removes it; otherwise it expires at the next circle-local midnight after composition began. An already-open, authorized composer keeps its working media through midnight.
- Resuming a draft rechecks entry with the server. An old entry grant cannot reopen a closed no-late window, and a draft never extends daily or evening entry deadlines. Failed uploads keep the recoverable draft. Drafts are not cloud-synced or guaranteed to capture the last instant before a crash.
- An author may edit the text or transcript and optional scripture tag for exactly ten minutes after `submitted_at`. The global limit is independent of circle settings, is enforced by the server, and never replaces the original audio, video, or photo.

### Circle activity notifications

- After submitting for a prompt, a current member may nudge another current member who has not shared for that exact prompt. Today exposes this only after the prompt starts, while entry is open or daily late sharing remains available. End-of-day nudges close at seven hours or the next daily start. Entry grants and the first-day exception never extend nudge eligibility before start/after close.
- A recipient gets at most one nudge per prompt across the entire circle, enforced transactionally. The ordinary circle activity switch controls nudges. The dispatcher rechecks sender/recipient membership, the entry window, recipient submission, and preferences before sending a regular notification (no Live Activity), with the sender's avatar and no blessing content/media. The notification routes to the exact prompt's Today composer.

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
- Today remains fixed horizontally, with no side-to-side bounce. Only attached blessing photos open a full-screen viewer; profile and circle photos remain decorative. The viewer supports with pinch/pan/double-tap and accessible zoom/reset/movement controls. Existing photo-editing and card-navigation actions are preserved.
- Each Today blessing uses one continuous panel for its content, scripture, response history, and composer. The blessing body and transcript are presented directly without redundant “Reflection,” “Transcript,” or “Responses” headings.
- Responses can be authored directly from Today. A current-day blessing opened from Timeline may also accept a response; historical Timeline details are read-only.
- Response history shows the responder's profile photo beside their name; Timeline cards continue to show compact responder icons.

### Timeline

- List is the default for everyone. Its person filter offers All or a specific member and applies only to List; Threads always shows every member. The selection survives mode changes, refresh, and paging, and resets on account/circle/time-zone changes or removal of the selected person. Filtered-empty results retain the older-history action when more pages exist. A wide, thin, labeled Timeline layout control in a pinned bar below circle navigation switches List/Threads with a minimum 44-point target. In List it sits beside the person filter at standard text sizes; accessibility sizes give the filter a full-width row. In Threads it remains above the pinned member header.
- Threads is a vertically scrollable timeline with a horizontal lane per member, each with a vertical thread. Profile photos and names sit in a compact fixed header below the pinned Timeline controls; they move with horizontal member scrolling but stay pinned vertically.
- Dates are viewport-anchored to the left of a continuous vertical divider with eight points of trailing padding. A full-height opaque strip hides body content beneath them, including the leading gutter and during horizontal overscroll. The date strip begins below the header, so it never masks profile photos or names. Body content cannot paint above the header's horizontal divider.
- Each daily event has a dated dot, content preview, and time.
- In Threads, a missed day has a distinct hollow marker and text label; color is never the only cue. List contains only actual blessing and membership events ordered newest first by their actual timestamps, without missed, waiting, or locked placeholder rows.
- Unstarted prompts and future calendar-day prompts have no Timeline placeholder. Current-day peer blessings remain gated until the viewer submits for that exact prompt.
- A pre-notification welcome blessing stored against yesterday's prompt appears on its actual sent date as Welcome blessing, after Joined circle. This is presentation only: the original prompt/privacy gate remains intact and a separate regular blessing is still available when today's notification starts. Welcome blessings do not count toward the regular/evening streak.
- The frozen date strip includes only the actual random blessing notification time in the circle's time zone; evening notification times are hidden while evening posts retain their sent-time labels. A projected welcome event does not copy yesterday's notification time onto today.
- Threads has compact cards and member headers. Pinch or use the Timeline menu's smaller/larger/reset controls to adjust column widths within readable bounds; fonts still honor Dynamic Type. Rows render lazily and presentation is cached independently of scroll offsets. List indexes chronological entries by person when data changes; changing the filter does not sort the entire history or fetch another page. Threads rows and date labels are prepared only while Threads is active; horizontal scroll geometry stays in the Threads component, and frozen dates look up only anchored rows.
- History starts with a fourteen-calendar-day page. Load older days adds whole-day pages, preserving both daily/evening events and membership boundaries. Switching account, circle, or time zone resets the paging scope; an in-flight older-page result cannot append to another scope. An older widget blessing link resolves its permitted detail without requiring manual page loading.
- Streaks are circle-specific and use each circle's calendar independently of loaded pages. The overall run counts completed random **or** evening blessings, once per authored day even if both are sent or either is late. The independent on-time run counts **only random** blessings with timely entry; evening-only days never earn blue credit. Timely entry remains entry before the random deadline, even when completion is later. Welcome, future, pre-start, and pre-membership posts are excluded.
- Posting resolves its own day immediately. An absent random post resets on-time at the actual random deadline; overall waits for the final actual daily/evening opportunity, bounding evening entry by the next random start. Pending overnight evening windows preserve the earlier overall run across midnight. Missing/unstarted evening windows use circle-midnight fallback rather than ending overall at the random deadline; an unstarted random prompt likewise never ends timely credit at its planned deadline. Server metadata supplies the next pending transition, and the app refreshes at that deadline while preserving account/circle scopes. Posting and reuse refresh streak metadata alongside content.
- Today and Timeline keep one small photo-overlay pill showing the overall count, blue only when it equals the positive consecutive on-time count, otherwise red. Names retain their placement beside photos. Circle People shows separate red overall and blue on-time pills for positive counts, red only when on-time is zero, and none when both are zero. A 5-day overall run with the last 3 random blessings timely shows red 5 on the photo, red 5/blue 3 in Circle, and both counts in the small animated icon-anchored popup. The popup includes zero counts. No verification icon or ranked leaderboard; Reduce Motion is respected.
- Past days are visible to members regardless of today's submission.
- Current-day peer content is replaced by a locked state until the viewer posts.
- Previews show up to 15 lines of original text or transcript plus the reference when present. Every member cell for a given day shares the height of that day's longest preview.
- Both List and Threads blessing previews show the total response count (including zero after a successful read) alongside slightly overlapping responder photos. Each person appears once, with the first five photos and a remaining-people count. Failed or cancelled reads do not imply zero. Response text/audio remain in the detail view. Visible cards share bounded, coalesced metadata-only response queries; short-lived summaries are scoped to the current account/circle and invalidated by refreshed Timeline data and successful response submission. They never load/sign response audio merely for icons.
- Tapping a blessing opens text, audio plus transcript, or video plus transcript. Audio exposes a seekable playhead; video preserves its original presentation aspect ratio and uses Apple's native inline/full-screen playback controls. An optional photo appears with text or audio content, tagged scripture appears before responses in the viewer's selected translation, and historical responses are view-only; current-day details may include the response composer.
- Playback adopts refreshed media URLs, invalidates older asynchronous preparation, and preserves CAF/M4A voice containers. Failed voice downloads retain sanitized HTTP/transport status in diagnostics; asset, playback, audio-session, and local staging errors record safe failure metadata without recording contents, raw error descriptions, or signed URLs. Cancellation is silent and retryable. An unavailable link prompts a page refresh; a generic playback error alone does not prove backend connection exhaustion.
- Each member lane stops at a “Joined circle” marker and never fabricates missed days before membership began.

### Later scope: widgets

- A widget shows “Time to share blessings for [circle name]” while any joined circle has an active prompt and deep-links to Today.
- Outside share time, it rotates blessings across all joined circles at a user-configured interval, defaulting to 30 minutes.
- Widget content includes scripture when present and uses transcripts for voice/video blessings. It prioritizes current-day, recent, and not-yet-shown blessings; before any prompt has fired today, it falls back to the most recent prior-day blessing.
- Widget timelines preload 24 hours of known prompt boundaries and rotation entries. Shared data is readable after the first device unlock; refreshes coalesce rather than repeatedly cancel, and temporary fetch failures retain the last usable snapshot. New server data still needs an app refresh and iOS controls delivery timing.
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
- Setup explains that server audio/video expires after 30 days, while text and photos remain. Automatic saving preserves available media on this device; leaving it off still permits manually saving individual blessings.
- See `docs/MEDIA_RETENTION.md` for storage, cleanup, and safe rollout details.

## Customer Help and circle setup

- Help is available from the hamburger menu both inside a circle and in the no-circle state. Illustrated, plain-language topics explain sharing, evening reflections, circles, Timeline, responses, saving/expiry, Bible tags, notifications/widgets, and personal settings. A Topics menu jumps between features without building a deep navigation stack.
- Every customer-visible feature change must update the matching Help topic and relevant tests.
- Creating a circle opens a full-screen guided page with progress and Back/Continue controls. Collect name, optional photo, time zone, random-time range, entry duration, late-sharing policy, end-of-day time, and repeat window one step at a time. Validate each relevant step; preserve selections on Back. A final review precedes the sole create action.

## Accessibility

- All common tasks use native named controls with 44-point minimum targets, Dynamic Type, adaptive colors, and explicit status text/symbols. Reduced Motion disables custom countdown/onboarding animations.
- Timeline offers Threads and a single-column List. List defaults on for VoiceOver and accessibility text sizes; it preserves membership boundaries, privacy gates, actual events, detail opening, and saved-media behavior. Placeholder statuses remain in Threads only. Spoken card names include author, circle-local date, prompt kind, capture mode, full text/transcript, late status, and Bible reference.
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
