# Security and privacy

Blessings can reveal religious beliefs, health, relationships, location, and other sensitive personal information. Treat all content as private by default.

## Security baseline

- Enforce membership and timeline visibility in Postgres RLS/security-barrier RPCs, not only in SwiftUI.
- Keep APNs signing keys and Supabase service-role credentials server-side.
- Store invite-code hashes; rate-limit and audit join attempts; allow code rotation.
- Use short-lived signed URLs for media. Never make the video bucket public.
- Validate MIME type, duration, size, ownership, prompt state, and deadline before finalizing media.
- Make submission and dispatch operations idempotent.
- Redact tokens, blessing bodies, and signed URLs from telemetry.
- Separate development and production projects, APNs environments, and storage buckets.

## Privacy baseline

- Ask for microphone, speech recognition, camera, photo library, notifications, and Live Activity access only at the point of use.
- Explain why each permission helps before showing the system prompt.
- Store voice transcription as editable text. Do not persist microphone audio for voice mode.
- Show clear retention behavior for submitted video, drafts, backups, and deleted accounts.
- Provide account deletion and circle-leaving flows; document how deletion affects shared history.
- Do not train models on blessing content or use it for advertising.
- Use aggregate operational metrics that do not contain blessing text or media.

## Threats to test

- guessing or brute-forcing invite codes;
- querying another circle by changing an ID;
- reading today's peer data before posting;
- submitting after the ten-minute deadline or submitting twice;
- replacing finalized media with another object;
- replaying a dispatch function or leaked signed URL;
- notification previews exposing sensitive content on the lock screen.

## Product safety

- Notification copy should say the circle is ready, not reveal blessing content.
- Add report, block/remove, and owner moderation before a public release.
- Provide a support path for harmful or crisis-related content without claiming the app provides counseling.

