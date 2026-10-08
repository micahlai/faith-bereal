# Media retention and private saved blessings

## Contract

- Blessing audio/video and response audio expire 14 × 24 hours after their own server `submitted_at`, not the circle day or prompt start. Text, transcripts, Bible references, photos, and response rows remain in hosted history.
- Saving never extends hosted retention and does not change anyone else's access. Each signed-in account has a private on-device archive, separate from Photos exports.
- Save blessing snapshots the blessing and currently visible responses, downloading attached photo, audio, and video before reporting success. Partial downloads never mark a blessing saved. It does not subscribe to future responses.
- Archives use Application Support, file protection, relative media paths, atomic manifests, and are excluded from cloud/device backup. They survive app launches, but not uninstall/device loss. Switching accounts cannot expose another account's saved media.
- Timeline still uses membership and server visibility rules. A saved copy supplies media for that existing blessing after hosted media expires; it does not unlock a current-day peer blessing.
- The first save explains device-only storage, snapshots, 30-day hosted retention, and loss on uninstall. Unsave removes the account's archive only. If any captured audio/video has expired, warn that deleting the local copy is permanent for that media.
- Timeline labels immediately above blessing cards show “Saved” and, for expiring unsaved audio/video, “Media expires in …” starting 48 hours before expiry. Voice response media also participates in the warning.

## Hosted cleanup

Storage bytes must be removed with the Storage API, not by deleting `storage.objects` rows. A service-role-only queue captures expired audio/video/thumbnail paths, clears the corresponding row references, and retries Storage removal after failures. Shared repeat paths are not removed while an unexpired blessing still references them. Photos, avatars, circle photos, and text are never cleanup targets.

The existing scheduler performs bounded cleanup batches. The migration does not execute a historical deletion during installation. Deploy the client archive feature before enabling cleanup for existing users; older media cannot be recovered after a cleanup run. Validate the transactional SQL fixture and Storage deletion on a disposable test object before production activation.

## Verification

Run `bash Scripts/test-media-retention.sh` with local PostgreSQL tools available. It creates an isolated socket-only temporary database, installs the real migration against a minimal compatible fixture schema, checks retention/privacy invariants, then stops and removes only that fixture. It never contacts hosted Supabase.

For rollout, push `202610080001_media_retention.sql` and deploy `dispatch-prompts` with cleanup left disabled. Verify a disposable hosted media fixture and ship the archive-capable app before setting the Edge Function secret `MEDIA_RETENTION_ENABLED=true`. Removing or setting that secret to `false` pauses new cleanup but cannot restore media already removed. Deployment/activation is a separate explicit release decision.

Cover exact 12/30-day boundaries, response dates, privacy/account isolation, archive reload, atomic partial failure, original-file preservation, local playback after expiry, unsave and expired warnings, locked content, repeat path references, queue retry, and add-only Photos permission. UI coverage uses local demo data, never hosted sign-in.
