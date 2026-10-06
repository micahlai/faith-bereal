# Milestone 2 deployment runbook

Milestone 2 is complete in source. This runbook is the credentialed environment handoff; it intentionally contains no private values.

## 1. Provision and link Supabase

Create separate development and production projects, then authenticate and link the CLI:

```sh
npx supabase login
npx supabase link --project-ref YOUR_DEVELOPMENT_PROJECT_REF
npx supabase db push
```

Confirm all migrations in `supabase/migrations` applied in order. The final migrations create auth-profile bootstrap/backfill, enable realtime tables, and add per-activity token registration.

## 2. Configure Sign in with Apple

In the Apple Developer portal, enable Sign in with Apple, Push Notifications, and Live Activities for `app.blessingcircle.ios`. Configure Apple's provider in Supabase Auth with the matching Services ID/team/key details. Build with the intended Apple Developer team and verify the app and widget extension are signed.

## 3. Configure the iOS app

```sh
cp Configuration/Secrets.xcconfig.example Configuration/Secrets.xcconfig
```

Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the untracked file, regenerate the Xcode project, and install on physical devices. The app uses the local repository if either value is absent.

## 4. Configure and deploy APNs dispatch

For the hosted function, Supabase automatically provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. Set only these custom secrets: `DISPATCH_SECRET`, `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_BUNDLE_ID`, and `APNS_PRIVATE_KEY`. The local `supabase/.env.local` file also needs the Supabase values when serving the function locally.

```sh
npx supabase secrets set --env-file supabase/.env.production
npx supabase functions deploy dispatch-prompts --no-verify-jwt
```

Schedule an authenticated request to `dispatch-prompts` at least once per minute. Use either `x-dispatch-secret` sourced from Vault or the Supabase dashboard Cron integration's server secret `apikey`. Keep both forms of server credential and the APNs `.p8` key out of the app and repository.

Do not treat a Cron row marked successful as proof that dispatch completed: inspect `net._http_response` and require a 2xx response body. A healthy idle run returns `{"claimed":0,"outcomes":[]}`. Interrupted prompts that are still open are reclaimed after five minutes; expired interrupted prompts are closed.

After deployment, sign into two physical devices as members of the same circle. From the owner's Circle settings, confirm **Force blessing notification** and verify that both accounts receive the alert and Live Activity, while a non-owner does not see the owner control.

## 5. Two-device acceptance

1. Sign in with two Apple accounts on two physical devices.
2. Create a circle on device A and join it on device B.
3. Change name, IANA time zone, random range, response duration, and late policy as owner; verify future prompts snapshot the new duration.
4. Confirm both devices receive the alert and push-to-start Live Activity at the same prompt instant.
5. Submit on A and verify B still sees today's peer blessing locked; submit on B and verify both timelines refresh without relaunching.
6. Exercise typed, voice/audio, video/transcript, optional scripture preview, and text/voice responses.
7. Confirm Live Activities update response count/completion and receive an explicit end event at the deadline.
8. Attempt cross-circle reads, duplicate submission, unauthorized owner settings, and late submission with both policy values.
9. Confirm a member who joins later sees “Joined circle” with no earlier missed markers.

Record APNs response reasons, accepted/attempted counts, Edge Function logs, migration output, and the two-device test result without logging tokens, signed URLs, blessing text, or media. TestFlight registers Production tokens, so a Sandbox-device pass is necessary but not sufficient for release.
