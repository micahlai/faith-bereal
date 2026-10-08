# Agent operating guide

Read `docs/STATUS.md` first, then the relevant spec before editing.

## Product invariants

1. A daily prompt belongs to one circle and has one server-authored start time.
2. The response window is exactly ten minutes from the server-authored start time.
3. Past history is visible to circle members. Today's peer posts stay locked until the current user submits today's post.
4. One user can create at most one post per prompt. The server, not the UI, enforces this.
5. A post records exactly one capture mode: typed, voice-transcribed text, or video. Voice transcription is stored as text, not raw microphone audio.
6. Never embed service-role, APNs, or Apple private keys in the app.
7. The local demo backend must remain usable for previews, tests, and simulator development.

## Engineering conventions

- Swift 6, SwiftUI, Observation, structured concurrency, and protocol-based services.
- Keep views declarative; business rules belong in models/services.
- Use semantic colors and Dynamic Type. All interactive targets must be at least 44 by 44 points.
- Treat dates as UTC in storage and convert only for display.
- Add or update tests for business-rule changes.
- Update `docs/STATUS.md` when a milestone materially changes.
- Whenever customer-visible behavior changes, update the matching topic in `Sources/Features/Help/HelpContent.swift` and its guide tests in the same feature change. Keep Help free of backend jargon and explain limits honestly.

## Verification

Generate the Xcode project with `xcodegen generate`, then build and test with the commands in `docs/TESTING.md`.
