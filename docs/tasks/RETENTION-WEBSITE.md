# RETENTION-WEBSITE: Match the audio/video rollout policy

- **Goal:** Published website accurately describes the selected retention scope and launch grace period.
- **Folder:** /Users/micahlai/code/manna circle website only.
- **Contracts used:** Existing privacy/support pages and policy tests; no app interfaces.
- **Done when:** Policy and tests match, lint/test/build pass, production published and fetched, changes committed on existing website branch.
- **Notes:** User chose audio/video plus response audio removal after 30×24h; keep text/transcripts/Bible references/photos. Cleanup remains disabled until THREE DAYS AFTER the updated 0.5.0 build is actually available; that date is unknown, do not invent it. Physical Supabase/R2 deletion retries may delay completion. Device saves do not sync or survive uninstall, may grow indefinitely; auto saving on for new users, explicit older choices preserved, app-open/connection/storage limits, 3-day reminder can be hidden. No exact guaranteed wall-clock physical deletion promise. Reuse existing deployment authorization/workflow; no other features/dependency changes. App spec: ../faith-bereal/docs/MEDIA_RETENTION.md (being updated now).
