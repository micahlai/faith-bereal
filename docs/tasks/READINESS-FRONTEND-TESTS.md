# RF1: Frontend functionality acceptance

- **Goal:** Establish which current SwiftUI workflows pass and identify actionable functional failures before release.
- **Folder:** Only `build/frontend-readiness/` may be written; app source, tests, docs and artwork are read-only.
- **Contracts used:** Existing Debug local-demo launch flags and UITests; current source 0.5.3 (50), baseline c44c1cc.
- **Done when:** Current full UI run is accounted for; failures are reproduced/classified with exact test names and evidence; untested release flows and device requirements are clearly listed in a concise report.
- **Notes:** Read docs/TESTING.md and relevant PRODUCT_SPEC/Help; current full suite is running with log build/app-store-readiness-nov03-ui.log and result build/AppStoreReadinessNov03UI.xcresult. Do not start another full run or rebuild while it runs. No hosted writes/accounts/APNs. No artwork work. User permits screen access only from Chrome; do not control/screenshot Simulator/native apps. XCUITest artifacts/logs may be inspected as local test evidence.
- **Verification:** Keep original failing results; focused reruns may classify failures but must not erase them. No test weakening or source edits. Reuse current compiled Debug products and isolated simulators for necessary focused checks. Report 44-point targets, largest text, loading/offline, capture, playback, saving and privacy/onboarding functionality coverage, plus missing report/block/deletion UI flows.
