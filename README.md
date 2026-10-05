# manna circle - daily blessings

manna circle is an Apple-native daily gratitude app. At one unpredictable moment each day, every member of a private circle gets the same time-limited invitation to share a blessing by typing, dictating, or recording a short video.

This repository contains:

- a SwiftUI iOS app;
- an ActivityKit widget extension with local and remote push-to-start/update/end support;
- a Supabase production adapter, schema, storage policies, realtime subscriptions, and APNs Edge Function;
- product, design, security, architecture, and delivery documents intended to keep human and coding-agent work aligned.

## Project state

Milestones 0–2 are implemented in code. Without backend secrets, the app automatically uses deterministic local data; adding an untracked `Configuration/Secrets.xcconfig` switches composition to Supabase Auth, Postgres, Realtime, Storage, and APNs registration. Hosted deployment and physical-device signing require the project owner's Supabase and Apple Developer credentials.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Backend and data model](docs/BACKEND.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Roadmap](docs/ROADMAP.md)
- [Project status](docs/STATUS.md)
- [Security and privacy](docs/SECURITY_PRIVACY.md)
- [Testing strategy](docs/TESTING.md)
- [Milestone 2 deployment runbook](docs/MILESTONE_2_RUNBOOK.md)

## Local development

Requirements: Xcode 26+, iOS 18+ simulator, and XcodeGen.

```sh
xcodegen generate
open BlessingCircle.xcodeproj
```

Copy `Configuration/Secrets.xcconfig.example` to `Configuration/Secrets.xcconfig` and fill in the public Supabase values to use the production adapter. If that file is absent or blank, the app uses seeded local data. No secrets are committed.
