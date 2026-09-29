# Blessing Circle

Blessing Circle is an Apple-native daily gratitude app. At one unpredictable moment each day, every member of a private circle gets the same ten-minute invitation to share a blessing by typing, dictating, or recording a short video.

This repository contains:

- a SwiftUI iOS app;
- an ActivityKit widget extension for the ten-minute response window;
- a Supabase schema and server-function plan for accounts, circles, schedules, posts, media, and APNs delivery;
- product, design, security, architecture, and delivery documents intended to keep human and coding-agent work aligned.

## Project state

The first vertical slice is being implemented against a local demo backend so the full experience can be built and tested without credentials. Production Supabase and Apple Developer setup is documented in `docs/BACKEND.md` and `docs/ROADMAP.md`.

## Documentation

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Backend and data model](docs/BACKEND.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Roadmap](docs/ROADMAP.md)
- [Project status](docs/STATUS.md)
- [Security and privacy](docs/SECURITY_PRIVACY.md)
- [Testing strategy](docs/TESTING.md)

## Local development

Requirements: Xcode 26+, iOS 18+ simulator, and XcodeGen.

```sh
xcodegen generate
open BlessingCircle.xcodeproj
```

The default Debug configuration uses seeded local data. No secrets are committed.

