# Offline blessings and 90-second video

Decision record: October 24, 2026. The user chose a **10-minute entry grace period** after the ordinary deadline. This is an implementation plan, not shipped behavior. The current client still obtains a server entry grant before opening capture; it has no automatic outgoing-post queue. Video capture still stops at 30 seconds.

## Write immediately; authorize sending separately

Today should offer Write a blessing as soon as the last signed-in account and a locally known circle are available, without waiting for session refresh, prompt fetch, Timeline, media signing, or the network. Writing grants no ability to read today's peer posts or edit circle settings. First-ever sign-in/circle discovery still needs a connection.

Store the composition privately under account + circle + a stable local composition ID. Save text, scripture reference, mode, copied media, intended daily/evening kind, and intended circle-local date. A known prompt ID stays fixed. With no verified prompt, save an **unbound draft**, not a fabricated prompt. Explain which circle and daily/evening blessing it is for. A stale cached schedule is a display hint only.

The user must tap **Send when connected** to queue a blessing. Checkpointing, closing the composer, and merely reconnecting must never publish an unfinished draft. Show Saved on this device separately from Waiting to send. Offer Edit and Cancel while waiting; serialize edits against an active send and freeze its payload once a send begins. Use a revision and immutable submission ID so a delayed retry cannot publish an older edit.

## Deadline rule

Let D be the server-authored entry deadline and G = D + 10 minutes. Use the server's clock, membership, actual prompt start, and circle day, never a client-reported offline/start time.

| Server state when reconnection reaches entry authorization | Result |
| --- | --- |
| Prompt not started | Keep the composition locally; wait for the invitation. Never unlock peers or send early. |
| Entry still open, before D | Obtain the ordinary server grant and send. |
| Daily prompt, late sharing disabled, D ≤ now < G | Obtain a server grant with the actual late entry time; send as late. |
| Daily prompt, late sharing disabled, now ≥ G | Keep text and media as an unsent draft with an explanation. No silent deletion or reassignment to tomorrow. |
| Daily late sharing enabled | Existing late-sharing/day boundary applies; do not shorten it to ten minutes. |
| A valid entry grant already exists for this outgoing blessing | Resume the authorized upload/submission after D or G, including after midnight; retain the original prompt. |
| Membership removed, account changed, already posted, or target cannot be resolved safely | Stop auto-retries and retain the local composition for review. |

Use a half-open grace interval: exactly G is closed. An already granted composition may finish afterward, matching the existing rule that deadlines control entry rather than upload completion. “Reconnect within ten minutes” means the server actually receives and accepts the authorization request in time, not merely that Wi-Fi becomes available. Compression or upload need not finish in the grace interval.

The grace is **available to any new entry** during those ten minutes. No reliable offline proof exists on an ordinary client. Do not describe it as a loophole-free offline exception or grant on-time streak credit to a late entry. Store `entered_at` as the actual server time; retain the existing separate late submission label and on-time streak rules.

Recommended boundary: apply this grace to the **daily timed entry deadline only**. Never use it to reopen a past circle day or a welcome blessing. Preserve the evening rule (seven hours or the next daily start, whichever comes first); do not add grace after another prompt has superseded it. If a daily deadline crosses midnight, preserve its existing valid entry interval, but do not extend entry past the existing day cutoff merely for offline grace. These boundary choices should be explicit in Help and SQL tests.

Examples: an ordinary deadline of 3:10 p.m. permits a grace grant at 3:19:59 p.m.; 3:20 p.m. is rejected. A 3:19 p.m. server grant permits a 90-second video to upload after 3:20. A device reconnecting at 3:21 keeps its writing locally. A blessing whose original grant was recorded at 3:05 may finish later without using the grace exception.

## Implementation sequence

1. Introduce a protected account-scoped composition/outbox store, atomically saving media before its manifest, with recoverable states: draft, waiting for invitation, queued, requesting entry, uploading, submitting, sent, needs review. Keep pending sends separately from the current draft's next-midnight cleanup so an unsent queue item is never discarded on rollover. Retain a rejected queued draft until the user sends elsewhere explicitly or discards it; provide storage management.
2. Add a cached prompt/context display store with exact prompt identity, kind, circle time zone/day, and observed server timing. Keep it separate from the existing metadata cache, which deliberately contains no prompts. Resolve an unbound draft only against the matching server circle/day/kind and require review if ambiguous. Never silently bind an expired daily draft to an evening or next-day prompt.
3. Split `AppModel.openCapture` into immediate local composition and asynchronous server entry acquisition. Start acquisition immediately when online, even before Send, preserving the existing enter-in-time/finish-later behavior. Persist its prompt association. If it fails offline, keep writing. Preserve business checks at the repository/server boundary; local composition alone cannot set `canUseFreshCircle` or unlock peers.
4. Add a backward-compatible, server-authorized queued-entry operation and migration. Enforce membership, actual start, exact target prompt, ten-minute daily grace and hard boundaries, uniqueness, and actual server timestamps. Do not trust caller-supplied entered-at values. Make repeated claims for the same immutable outgoing ID idempotent; resume a previously granted send without requiring a new closed-window entry. Keep the ordinary entry RPC compatible with installed clients, and update submission/media authorization consistently.
5. Add a single outgoing worker per account, serializing each prompt's send. Restore the queue at launch; resume on authenticated foreground network recovery, explicit Retry, and foreground refresh. Obtain entry before expensive export/upload. Persist each completed upload slot and reuse it on retry; reconcile a lost success response against the server uniqueness key before retrying. A second device's successful post must stop this queue item without replacing that post. Keep failures separate from successful posting and privacy unlock.
6. On sign-out/account switch, stop and fence the worker and keep queued content inaccessible to other accounts. Choose explicit sign-out copy for pending drafts rather than silently sending or deleting them. Handle disk-full failure before displaying Waiting to send. Never promise that iOS will execute the queue while the app is closed; the first version sends while manna is active and resumes when reopened.
7. Implement the same deadline/grant/queue behavior in the local demo with an injected clock. Update the product spec, sharing/evening/saving Help and guide tests together with the feature. Ship the SQL compatibility change before enabling the client worker.

Verification must cover before/at/after both deadlines; spoofed device clocks; delayed session/context/page reads; offline cold launch; unknown/scheduled/changed prompts; midnight, DST, welcome and evening cutoffs; expired/renewed authentication; member removal; lost upload/submission responses; repeated taps; concurrent workers/devices; account changes/sign-out during each awaited stage; local media after relaunch; edits/cancel against an active send; disk-full recovery; and today's peer lock before confirmed server acceptance. Test the migration in disposable PostgreSQL and a rollback-only hosted trial before any approved deployment.

## Raising video from 30 seconds to 1:30

Current code sets `UIImagePickerController.videoMaximumDuration = 30` and shows Record up to 30 seconds. All new/restored videos export network-optimized MP4 at 720p. Resolution is capped, but bitrate and file size are not; the export preset is not a byte budget. The checked-in media bucket limit is 75 MiB; the live global/bucket settings have not been inspected for this task.

At equal average bitrate, duration triples, so recording bytes, upload/download time, storage and complete first-play transfer scale roughly threefold. This is an estimate, not a measured property of Apple's preset:

| Total average bitrate | 30 seconds | 90 seconds |
| --- | ---: | ---: |
| 1 Mb/s | 3.75 MB | 11.25 MB |
| 2 Mb/s | 7.5 MB | 22.5 MB |
| 4 Mb/s | 15 MB | 45 MB |

Values use decimal MB and include audio only if it is already included in the stated total bitrate. At 2 Mb/s, a 90-second clip needs roughly 90 seconds to upload over a sustained 2 Mb/s upstream connection, before export/request overhead. Every uncached complete playback by another member adds another copy's transfer; local identity-photo storage does not offset video bytes. Shorter actual recordings need less.

Longer capture also means longer camera/microphone use, export and transcription, more battery/temporary-disk demand, and potentially more export/SDK buffer memory pressure (the video upload path already uses a file URL; measure peak memory on a phone). The 1,200-character transcript limit is unchanged; a 90-second spoken message may require editing/trimming even when the recording is accepted. The 30-day hosted retention, 720p ceiling, post uniqueness, privacy and ten-minute post-edit window should stay unchanged.

Recommendation: 90 seconds is feasible, but pair it with a validated output byte limit (proposed 25 MB), a target average bitrate budget around 2 Mb/s including audio, actual file-size/duration checks for all incoming/restored video sources, clear export/upload progress and resumable retries. Do not assume 720p alone meets that budget. Re-export lower if necessary or explain how to shorten the clip before upload. Confirm the hosted global limit as well as the bucket limit: Supabase documents a 50 MB maximum global limit on Free projects and requires per-bucket limits at or below the global limit. Its docs recommend resumable uploads for files above 6 MB or unstable networks. See [file limits](https://supabase.com/docs/guides/storage/uploads/file-limits) and [resumable uploads](https://supabase.com/docs/guides/storage/uploads/resumable-uploads).

Before enabling 90 seconds, verify short/exact/over-limit clips, portrait/landscape, imported/restored clips, transcript overflow, low disk, interruption/backgrounding, slow cellular, retry after expiration, playback after saving, and hosted upload-size rejection on physical devices. Obtain the entry grant before recording/export when online, or immediately on reconnect when offline; do not make upload completion fit inside the grace period. No video-limit change is included in this branch.
