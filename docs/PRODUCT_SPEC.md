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
- Account-scoped display metadata (circle details, members, streaks, profile/circle photos) can appear immediately during startup and switching. Fresh basic metadata is saved before the blessing page finishes, so a failed or stalled first page does not prevent reuse on the next launch. Protected local metadata and downloaded identity-photo bytes remain in Application Support without an age expiry; photos load locally first and refresh only from fresh metadata. Known member and circle photos are downloaded even if their views have not appeared. Each source and decoded image remains size-limited; sign-out removes the outgoing account cache. Cached invitations/permissions never authorize sharing or edits, and blessings/prompts/responses are not restored from this cache. Each page has an explicit loading/error indicator and Retry on the page background color with contrasting text; tabs remain usable. Foreground refreshes coalesce, and optional widget/automatic-saving reads wait for visible loading to finish.
- A circle switch installs its fresh content only if the account and selected scope still match. An interrupted switch keeps the previous circle selected, restores live updates, and can be retried. Delayed Timeline pages and refresh errors cannot overwrite a newer account/circle/time-zone scope, even if the user later returns to its previous IDs.

### User settings

- Sign-in uses the manna wordmark. Sign out is located only in User settings, not the global menu or Circle page.

- Initial US-only, 13+ launch uses one styled, reversible seven-step setup: About, Appearance, App Icon, Your Privacy, Your Profile, Local Saving, and Widget. The privacy page follows logo choice and requires age/data-use agreement before bootstrap, sign-in or profile upload; optional diagnostics start off. Every step after the first provides Back and Continue controls. App-icon choices use the real cream and midnight artwork in equal one-column cards, and the widget page briefly explains both prompt and rotating-blessing states plus Apple's Home Screen installation steps. Accounts which completed the older setup are asked only for the new local-saving choice and widget reminder.
- A global hamburger menu opens user settings and circle management from every primary tab.
- Bible translation is an account-wide preference in user settings, not a circle setting.
- Appearance is an account-wide preference with system, light, and dark choices.
- User settings offers optional Share diagnostic data for field testing, including TestFlight. In 0.5.0 sharing defaults off and requires fresh consent; legacy default-on queues are disabled/discarded, while explicit off choices survive updates and relaunch. Settings disclose the default and allow disabling. It collects typed timing/size/outcome metrics, sanitized failure sources and short structured error codes, app build, and a random session code. Backend connection-limit classification and Speech/audio errors are included without transmitting their messages. Upload failures queue one record per distinct source/code/category until a successful send. Pending failures take priority over routine samples, while frozen retries remain exact; queue pressure discards routine records first. Reports are linked to the authenticated account and cannot be read by peers. No names, blessing content, media, paths/URLs, credentials, or error descriptions enter the payload. Bounded foreground batches retry idempotently with a protected device queue and 14-day server retention/periodic cleanup. Opt-out drops unsent records; an in-flight upload may finish. Local demo keeps records on-device. See `TESTFLIGHT_FIELD_TESTING.md` for limits/operator access.
- Bible translations are grouped by language, with language groups ordered by broad usage and translations clearly labeled by language and abbreviation.
- User settings list every joined circle with separate switches for peer blessing/followed-response alerts and the end-of-day reminder. Both default on.

### Daily prompt

- One prompt per circle per local calendar day.
- The local demo starts its sample daily prompt on the current local day, even when opened during the first minute after midnight, and preserves its exact ten-minute timer window.
- Random start time is selected server-side within a circle-configured window, default 12:00–22:00, with late blessings enabled by default.
- Circle creation transactionally schedules the current local-day prompt from the owner's initial settings. On the circle-local day a member joins, a welcome blessing belongs to yesterday until today's notification starts; afterward it belongs to today and entry is allowed until that day ends. An entry grant preserves that original date when sending later.
- The preselected random time is the dispatch target. When the server claims that prompt, it authors the shared `starts_at` from the actual dispatch and sets `ends_at = starts_at + response_window_minutes`, giving every member the complete configured entry window.
- A scheduled target passing does not itself open sharing or close welcome/evening entry. Hosted clients and authorization preserve scheduled state until the server starts that notification.
- The response deadline controls entry into capture, not completion of a capture already opened. The server records an entry grant before presenting capture; that grant remains valid if composition or upload finishes after the deadline or after midnight.
- A notification and Live Activity deep-link to today's capture screen.
- Device registration accepts alert and Live Activity tokens independently, preserving an existing token when the other is unavailable. Registration remains authenticated and requires an explicit production or sandbox environment. Reopening the app retries failed registration; iOS still controls delivery.
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

- Photo attachment source buttons keep their labels intact: Take photo/Upload become Retake/Replace after attachment, share a row only when both fit, and otherwise stack. Remove and preparation feedback use separate rows so they cannot squeeze the source buttons. Controls keep their 44-point minimum targets.

- Typed: multiline text, 1–1,200 characters, with an optional captured or uploaded photo. The same 1,200-character maximum applies to voice/video transcripts and edits; response text/transcripts remain limited to 600. Character counters match the database's Unicode-scalar length (combined emoji/accents can count as multiple characters), and capture truncation never splits a displayed grapheme.
- New video uploads are consistently exported as network-optimized MP4 at a maximum of 1280×720, including restored/imported video. Existing hosted recordings remain unchanged.
- Voice: in-app live transcription that the user can edit before submission, with private audio playback in detail and an optional captured or uploaded photo.
- Video: camera capture with editable transcript and private playback.
- Optional scripture tag: book and chapter dropdowns, then a drag-select square verse grid. Preview in the user's chosen public-domain Bible translation before sending.
- Submission shows an explicit progress state and cannot be duplicated by repeated taps.
- The server is authoritative for membership, prompt state, entry deadline, entry grants, and uniqueness. A client cannot create a post-deadline grant by changing its clock.
- When eligible, capture offers a quiet “Reuse a recent blessing” action. It preserves the original capture format, message/transcript, Bible reference, and attached audio, photo, or video as a new blessing in the target circle. Hosted media references are reused without re-uploading; target-circle members can read them only through the target blessing's visibility gate. Responses are not copied. It never exposes unavailable or expired reuse choices.
- Voice capture records playable audio while producing an editable transcript. Every completed voice recording, including a single segment or restored draft, is exported as compressed AAC in M4A before submission. Capture previews and submitted voice content include play/pause, elapsed and total time, and a seekable playhead. Camera capture owns its recording lifecycle and handles authorization, interruption, denial, and unavailable hardware on physical devices.
- Voice recording keeps the screen awake only while actively recording; pause, stop, interruption, backgrounding, or leaving capture restores normal sleep behavior. Blessing and response recorders share this ownership rule.
- In-progress blessings checkpoint text, scripture, capture mode, and local media privately on this device, isolated by account, circle, and prompt. The ordinary daily or end-of-day sharing action on Today changes to Continue for its own eligible saved draft, restoring unsent changes without a separate draft button. Successful submission removes it; otherwise it expires at the next circle-local midnight after composition began. An already-open, authorized composer keeps its working media through midnight.
- Resuming a draft rechecks entry with the server. An old entry grant cannot reopen a closed no-late window, and a draft never extends daily or evening entry deadlines. Failed uploads keep the recoverable draft. Drafts are not cloud-synced or guaranteed to capture the last instant before a crash.
- An author may edit the text or transcript and optional scripture tag for exactly ten minutes after `submitted_at`. The global limit is independent of circle settings, is enforced by the server, and never replaces the original audio, video, or photo.

### Circle activity notifications

- After submitting for a prompt, a current member may nudge another current member who has not shared for that exact prompt. Today exposes this only after the prompt starts, while entry is open or daily late sharing remains available. End-of-day nudges close at seven hours or the next daily start. Entry grants and the first-day exception never extend nudge eligibility before start/after close.
- A recipient gets at most one nudge per prompt across the entire circle, enforced transactionally. Today places nudges below all shared daily blessings. The button changes to Nudged without a native popup; failures appear inline with Retry. Nudges are independent of both per-circle notification switches; iOS notification permission still applies. The dispatcher rechecks sender/recipient membership, the entry window, recipient submission, and interaction safety before sending a regular notification (no Live Activity), with no blessing content/media. The notification routes to the exact prompt's Today composer.

- New blessing alerts identify the sender with their name/profile photo and circle name. Recipients who have shared for the exact same prompt receive the blessing text, Bible reference and available photo/video preview; other recipients receive “Share to see” with no blessing content or attached-media URL. Response and nudge alerts retain generic wording without identity/content fields. Routes still respect current submission locks and current authorization. Widgets and Live Activities have their separately disclosed device-visible content.
- Notification events are transactionally queued and dispatched server-side; clients cannot broadcast fabricated alerts. See [launch privacy evidence and physical acceptance limits](LAUNCH_COMPLIANCE.md).

### Today

- Blessing cards show saved-copy status without per-blessing Save/Unsave buttons. Automatic saving and the expiry review preserve private device copies; photo/video export to Photos remains separate.

- Before a prompt starts, Today shows the waiting state. During an open prompt, it shows the response timer and capture action until the viewer submits.
- After submission, Today becomes a vertically scrolling, full-width feed of every visible blessing for that circle's current prompt, including text/transcript, media preview or playback, optional full scripture passage, and responses.
- Today remains fixed horizontally, with no side-to-side bounce. Attached blessing photo previews preserve the original aspect ratio within their width/height limits. Opening or closing the black-background viewer does not override the selected app appearance. Only attached blessing photos open a full-screen viewer; profile and circle photos remain decorative. The viewer supports with pinch/pan/double-tap and accessible zoom/reset/movement controls. Existing photo-editing and card-navigation actions are preserved.
- Each Today blessing uses one continuous panel for its content, scripture, response history, and composer. The blessing body and transcript are presented directly without redundant “Reflection,” “Transcript,” or “Responses” headings.
- Responses can be authored directly from Today. A current-day blessing opened from Timeline may also accept a response; historical Timeline details are read-only.
- Response history shows the responder's profile photo beside their name; Timeline cards continue to show compact responder icons.

### Timeline

- Photo thumbnails preserve the original aspect ratio within the card width and 160-point height cap. Tall photos appear narrower instead of stretching to fill the card. Today and blessing details use the same aspect-preserving layout with a 520-point height cap. New preview generation uses the orientation-aware image dimensions, including rotated/mirrored camera JPEGs. Already-created remote previews are unchanged. Cards/details prefer a saved or already-cached original when present; opening the full photo and reopening the blessing/app can bypass an old distorted preview while that account-scoped temporary original remains cached. Scrolling never downloads a full original on a cache miss.
- List is the default on a new installation. The last chosen List/Threads layout persists on this device across tabs, circles and relaunch. List omits the thread line and circle markers. Its person filter offers All or a specific member in a photo picker, with initials for missing photos and the selected person’s photo beside their name, and applies only to List; Threads always shows every member. The selection survives mode changes, refresh, and paging, and resets on account/circle/time-zone changes or removal of the selected person. Filtered-empty results retain the older-history action when more pages exist. A wide, thin, labeled Timeline layout control in a pinned bar below circle navigation switches List/Threads with a minimum 44-point target. In List it sits beside the person filter at standard text sizes; accessibility sizes give the filter a full-width row. In Threads it remains above the pinned member header.
- Threads is a vertically scrollable timeline with a horizontal lane per member, each with a vertical thread. Profile photos and names sit in a compact fixed header below the pinned Timeline controls; they move with horizontal member scrolling but stay pinned vertically.
- Dates are viewport-anchored to the left of a continuous vertical divider with eight points of trailing padding. A full-height opaque strip hides body content beneath them, including the leading gutter and during horizontal overscroll. The date strip begins below the header, so it never masks profile photos or names. Body content cannot paint above the header's horizontal divider.
- Each daily event has a dated dot, content preview, and time.
- In Threads, a missed day has a distinct hollow marker and text label; color is never the only cue. List contains only actual blessing and membership events ordered newest first by their actual timestamps, without missed, waiting, or locked placeholder rows.
- Unstarted prompts and future calendar-day prompts have no Timeline placeholder. Current-day peer blessings remain gated until the viewer submits for that exact prompt.
- A pre-notification welcome blessing stored against yesterday's prompt appears on its actual sent date as Welcome blessing, after Joined circle. This is presentation only: the original prompt/privacy gate remains intact and a separate regular blessing is still available when today's notification starts. Welcome blessings do not count toward the regular/evening streak.
- The frozen date strip includes only the actual random blessing notification time in the circle's time zone; evening notification times are hidden while evening posts retain their sent-time labels. A projected welcome event does not copy yesterday's notification time onto today.
- Threads has compact cards and member headers. Pinch or use the Timeline menu's smaller/larger/reset controls to adjust column widths within readable bounds; fonts still honor Dynamic Type. Rows render lazily and presentation is cached independently of scroll offsets. List indexes chronological entries by person when data changes; changing the filter does not sort the entire history or fetch another page. Threads rows and date labels are prepared only while Threads is active; horizontal scroll geometry stays in the Threads component, and frozen dates look up only anchored rows.
- History starts with a seven-calendar-day page. Load older days adds whole-day pages, preserving both daily/evening events and membership boundaries. Switching account, circle, or time zone resets the paging scope; an in-flight older-page result cannot append to another scope. An older widget blessing link resolves its permitted detail without requiring manual page loading.
- Streaks are circle-specific and use each circle's calendar independently of loaded pages. The overall run counts completed random **or** evening blessings, once per authored day even if both are sent or either is late. The independent on-time run counts **only random** blessings with timely entry; evening-only days never earn blue credit. Timely entry remains entry before the random deadline, even when completion is later. Welcome, future, pre-start, and pre-membership posts are excluded.
- Posting resolves its own day immediately. An absent random post resets on-time at the actual random deadline; overall waits for the final actual daily/evening opportunity, bounding evening entry by the next random start. Pending overnight evening windows preserve the earlier overall run across midnight. Missing/unstarted evening windows use circle-midnight fallback rather than ending overall at the random deadline; an unstarted random prompt likewise never ends timely credit at its planned deadline. Server metadata supplies the next pending transition, and the app refreshes at that deadline while preserving account/circle scopes. Posting and reuse refresh streak metadata alongside content.
- Today and Timeline keep one small photo-overlay pill showing the overall count, blue only when it equals the positive consecutive on-time count, otherwise red. Names retain their placement beside photos. Circle People shows separate red overall and blue on-time pills for positive counts, red only when on-time is zero, and none when both are zero. A 5-day overall run with the last 3 random blessings timely shows red 5 on the photo, red 5/blue 3 in Circle, and both counts in the small animated icon-anchored popup. The popup includes zero counts. No verification icon or ranked leaderboard; Reduce Motion is respected.
- Past days are visible to members regardless of today's submission.
- Current-day peer content is replaced by a locked state until the viewer posts.
- Previews show up to 15 lines of original text or transcript plus the reference when present. Every member cell for a given day shares the height of that day's longest preview.
- Both List and Threads blessing previews show the total response count (only when at least one response exists) alongside slightly overlapping responder photos. Each person appears once, with the first five photos and a remaining-people count. Failed or cancelled reads do not imply zero. Response text/audio remain in the detail view. Visible cards share bounded, coalesced metadata-only response queries; short-lived summaries are scoped to the current account/circle and invalidated by refreshed Timeline data and successful response submission. They never load/sign response audio merely for icons.
- Tapping a blessing opens text, audio plus transcript, or video plus transcript. Audio exposes a seekable playhead; video preserves its original presentation aspect ratio and uses Apple's native inline/full-screen playback controls. An optional photo appears with text or audio content, tagged scripture appears before responses in the viewer's selected translation, and historical responses are view-only; current-day details may include the response composer.
- Played unsaved audio/video and opened photos share an account-scoped disposable disk cache: up to seven days, 256 MB total, and 128 MB per file. Renewing a signed token does not redownload the same immutable path; concurrent downloads coalesce. Saving a played item copies available cached bytes into its permanent archive. Temporary files can be evicted by iOS and never substitute for a completed Save. Sign-out clears the outgoing account cache. Retry discards the temporary recording copy, preserving permanent saves.
- New attached photos upload a 480-pixel preview separately from their full photo. Cards fetch only this preview; older remote photos show an Open photo placeholder until tapped. Full photos load on opening. Saved local photos need no remote preview. Both full photos and previews follow the same visibility gate, including reused blessings. Profile/circle photo cache identity ignores token renewal but includes metadata version changes. Downloaded identity photos persist without a seven-day expiry, load locally before circle refresh, and remain available after an offline session-refresh failure. Successful refresh replaces changed photos or removes explicitly removed photos; explicit sign-out clears the outgoing account’s identity copies. Existing cache photos migrate to durable local storage.
- Playback adopts refreshed media URLs, invalidates older asynchronous preparation, and preserves CAF/M4A voice containers. Failed voice downloads retain sanitized HTTP/transport status in diagnostics; asset, playback, audio-session, and local staging errors record safe failure metadata without recording contents, raw error descriptions, or signed URLs. Cancellation is silent and retryable. An unavailable link prompts a page refresh; a generic playback error alone does not prove backend connection exhaustion.
- Each member lane stops at a “Joined circle” marker and never fabricates missed days before membership began.

### Later scope: widgets

- A widget shows “Time to share blessings for [circle name]” while any joined circle has an active prompt and deep-links to Today.
- Outside share time, it rotates blessings across all joined circles at a user-configured interval, defaulting to 30 minutes.
- Widget content includes scripture when present and uses transcripts for voice/video blessings. It prioritizes current-day, recent, and not-yet-shown blessings; before any prompt has fired today, it falls back to the most recent prior-day blessing.
- Widget and automatic-saving visible reads coalesce per circle, reuse freshly authorized visible data, and share the newest page for another circle. Automatic saving additionally pages the complete retained-recording inventory, including older parent posts with recent response audio. Their shared reads expire after 60 seconds; appearance refreshes reuse visible reads for up to 15 seconds. Pull-to-refresh and content changes force fresh reads. Account/circle changes invalidate pending results. Unchanged widget snapshots throttle writes for one minute; changed content publishes immediately.
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

- The canonical contract, launch grace, provider cleanup and verification requirements are in [MEDIA_RETENTION.md](MEDIA_RETENTION.md). Recording audio/video has a 30×24-hour target; text/transcripts/Bible references/photos remain in history. Physical cleanup retries can run later, and starts only three days after actual updated-build availability. It remains disabled until that release gate is recorded.
- Automatic saving starts on for new users and preserves existing explicit choices. It checks every accessible retained recording across joined circles using bounded pages, including older parents with recent response audio; there is no seven-day media cutoff. Include older history additionally pages old text/photos. Wi-Fi-only starts on. App-open, network, visibility and storage limits prevent any promise that every inactive device receives everything before server removal.
- Save/review and keep-copy selection menus use the app canvas and Timeline-style cards with photo previews, opt-in audio/video playback, transcripts, Bible references and voice-response previews. They use no native List/Form/picker rows; recording files are prepared only after Play. Selection and saving controls remain separate from media controls. Save all stays pinned while reviewing, including at accessibility text sizes; full-screen previews preserve keep/remove choices and do not resume automatic saving until the selection menu closes. The review reuses already-authorized response metadata instead of fetching it again for display.
- When automatic saving is off and at least one known accessible blessing has unsaved recordings due within three days, a pinned Timeline reminder opens a scrollable three-day removal review with individual and save-all actions. Still-available overdue recordings are included during launch grace. A separate account/device reminder setting hides/restores the banner without preserving recordings; the review remains reachable from settings. Incomplete checks and failed downloads never claim complete saving.
- Cards show saved-copy status and three-day expiry warnings, including response audio, without per-blessing Save/Unsave controls. A text-only saved record cannot imply that its unavailable recording is saved. User settings estimates completed archive storage for the current account, excluding temporary caches/drafts/Photos exports.
- Playback loads audio and video only after Play is tapped, including in previews; scrolling does not prepare remote media. Explicit manual and automatic saving still download available media for the archive. Saved audio/video/photos and response audio take priority before and after hosted expiry for playback, viewing, and export. Archive refreshes reuse each existing file by its immutable media slot, regardless of changed signed URLs, and download only new media. Completed saved blessings appear automatically in the ordinary Timeline and detail screen before session refresh, including without internet or circle metadata across relaunch. Saved responses and card counts read the archive without backend calls in this presentation. Offline content never grants live membership or mutation privileges. Current peer copies require an own saved blessing for the same prompt; old manifests lack prompt dates/time zones, so unpaired peer copies use a conservative 26-hour age boundary. Missing names fall back to generic circle/member labels. The normal authorized server page replaces this presentation when available. Historical local copies supplement that page even beyond its cursor, deduplicate by blessing ID as server pages arrive, and keep their local media priority. New account identity or successful explicit sign-out clears archive presentation. No separate saved-items menu or reader is shown. Older CAF archives with .data filenames stage the same local bytes as CAF for playback; new CAF saves retain .caf. Saved media also opens from the existing Timeline card after hosted expiry. Setup/settings and the removal review explain device-only storage and loss on uninstall/device loss. Photo/video export to Photos is independent.
- Automatic saving refreshes available text/responses for existing copies and reuses intact nonempty files; manual review saves refresh their selected copy. Turning automatic saving off pauses the worker while the user chooses all/mine/none/selected keep options. Kept automatic copies become manual, existing manual saves are preserved, and removal of expired captured media requires permanent-loss confirmation. Cancel leaves automatic saving on. Legacy individual exclusions remain respected.

## Customer Help and circle setup

- Help is available from the hamburger menu both inside a circle and in the no-circle state. Illustrated, plain-language topics explain sharing, evening reflections, circles, Timeline, responses, saving/expiry, Bible tags, notifications/widgets, and personal settings. A Topics menu jumps between features without building a deep navigation stack.
- Every customer-visible feature change must update the matching Help topic and relevant tests.
- Creating a circle opens a full-screen guided page with progress and Back/Continue controls. Collect name, optional photo, time zone, random-time range, entry duration, late-sharing policy, end-of-day time, and repeat window one step at a time. Validate each relevant step; preserve selections on Back. A final review precedes the sole create action.

## Accessibility

- All common tasks use native named controls with 44-point minimum targets, Dynamic Type, adaptive colors, and explicit status text/symbols. Reduced Motion disables custom countdown/onboarding animations.
- Timeline offers Threads and a single-column List. List is the initial default and the chosen layout is remembered across relaunch, including for VoiceOver and accessibility text sizes; it preserves membership boundaries, privacy gates, actual events, detail opening, and saved-media behavior. Placeholder statuses remain in Threads only. Spoken card names include author, circle-local date, prompt kind, capture mode, full text/transcript, late status, and Bible reference.
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

- Whether to lower the current 720p upload ceiling or add adaptive video encodings; audio/video retention is fixed at 30 days.
- Trademark and App Store availability checks for “manna circle - daily blessings” are required before release.

### Planned offline composition and video duration

The [offline capture and video plan](OFFLINE_CAPTURE_AND_VIDEO_PLAN.md) records the chosen 10-minute daily entry grace, queue semantics, unresolved-target handling, rollout and verification. It is proposed behavior; the current client still requires an entry grant before opening capture and records video up to 30 seconds.

## Storage migration staging

An optional server-side Cloudflare R2 mirror copies new/changed hosted media in the background with durable retries. Upload completion and every app read continue through Supabase. It covers private blessing/response media, avatars, and circle photos, plus version-specific replacement/deletion cleanup. It does not mirror the database or change local-demo behavior, current visibility rules, or sharing success. Existing-media backfill and authenticated R2 reads are separate rollout steps. See [CLOUDFLARE_STORAGE.md](CLOUDFLARE_STORAGE.md).

## Media publication (0.5.2)

- Circle photos, audio, video and response audio require no developer approval before publication. Normal membership and today’s own-submission gate still apply. Explicit report/rejection hides, suspension, mutual blocking and limited text filtering remain. Reports require daily operator review; no automatic image/audio screening is claimed.
- An already-shared nudge response triggers a fresh circle read and removes that member from the local nudge candidates for that prompt without claiming a nudge was queued. Blocked members are excluded from nudge candidates.

## Ready-circle notification badge (0.5.3)

The app icon badge counts distinct joined circles with at least one currently authorized, unsubmitted daily or end-of-day entry. Both prompt types in one circle count once. Submission, membership loss, suspension, elapsed entry windows and day boundaries remove opportunities; permitted late/welcome entry remains counted. It is independent of peer-post/response counts and per-circle alert preferences. A caller-scoped integer RPC refreshes in the app; a leased per-device server job sends quiet absolute badge-only APNs values, including zero, with token rotation, stale-ack fencing, bounded failure retries and no alert/sound/content payload. Existing minute scheduling reconciles closed-app badges. Badge visibility and delivery depend on iOS permissions/network; this is not a guarantee of immediate background delivery. Sign-out revokes that account's installation notifications and clears its local badge; already issued pushes cannot be recalled.

## Circle switcher readiness

The circle-name dropdown lists joined circles only; join/create remains available from Manage circles and the Circle tab. A dot means at least one daily or end-of-day blessing is ready **and unanswered** for the current account. Both prompt kinds in one circle produce one dot; sharing one leaves it while the other is ready and unanswered. A caller-scoped IDs RPC reuses the badge predicate, and the app derives the badge count from those IDs. Failures retain the last successful result; sign-out clears IDs and stale reads cannot replace newer/account results. Refresh occurs on menu opening, existing metadata/mutation paths and foreground refreshes.

### Safety recovery and deletion-screen accessibility

Report details and selected reason remain available after a failed send; Done above the keyboard exposes the form actions. A blocked-user load failure presents an error and Retry instead of claiming the list is empty. Blocked-member names and Unblock stack at accessibility text sizes. The account-deletion pending screen scrolls with untruncated text and reachable status, policy, support and sign-out actions at the largest text sizes. A failed sign-out preserves the pending access gate; only successful sign-out dismisses it. Local Debug automation uses isolated synthetic safety/deletion services; real Apple confirmation is still required in distributed builds.
Deletion cancellation and request errors remain on Delete account with status/retry actions instead of dismissing the settings sheet through a global alert. A block failure keeps the blessing detail open with an error so the user can retry without navigating back.
