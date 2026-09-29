# Product specification

## Product promise

Blessing Circle creates a small, shared interruption for gratitude. The experience should feel intimate and present—not optimized for likes, streak anxiety, or public reach.

## Audience

Small trusted groups: families, friends, faith groups, teams, and communities that want a lightweight daily gratitude practice.

## Core loop

1. A person signs in with Apple and creates or joins a circle with a short code.
2. The server chooses one random daily moment for the circle within its configured waking window.
3. At that moment, APNs alerts every member and starts a ten-minute Live Activity.
4. A member opens the capture flow and shares one blessing as typed text, speech-transcribed text, or a short video.
5. After submitting, today's blessings from peers unlock. Prior days remain visible at all times.
6. When the window closes, members without a post receive a missed marker in history. Late submissions are rejected by the server.

## Functional requirements

### Identity

- Sign in with Apple is the production identity provider.
- A profile contains a display name, optional avatar, locale, time zone, and notification preferences.
- Account deletion removes profile data and schedules media deletion.

### Circles

- Create a circle and receive a human-readable, case-insensitive invite code.
- Join by code, leave, and view members.
- The circle owner can rotate the invite code and remove members.
- MVP supports one active circle per user in the UI; the schema supports multiple memberships.

### Daily prompt

- One prompt per circle per local calendar day.
- Random start time is selected server-side within a circle-configured window, default 08:00–20:00.
- Start time is immutable after publication and identical for all circle members.
- Response deadline is `starts_at + 10 minutes`.
- A notification and Live Activity deep-link to today's capture screen.

### Capture

- Typed: multiline text, 1–600 characters.
- Voice: in-app live transcription that the user can edit before submission.
- Video: camera capture, maximum 30 seconds for MVP, with a generated thumbnail.
- Submission shows an explicit progress state and cannot be duplicated by repeated taps.
- The server is authoritative for membership, prompt state, deadline, and uniqueness.

### Timeline

- A horizontally scrollable lane per member, each with a vertical thread.
- Each daily event has a dated dot, content preview, and time.
- A missed day has a distinct hollow marker and text label; color is never the only cue.
- Past days are visible to members regardless of today's submission.
- Current-day peer content is replaced by a locked state until the viewer posts.
- Video opens in an accessible player sheet; text supports Dynamic Type.

## Visibility policy

For a member `viewer`, prompt `P`, and peer post `X`:

- if `P` is before today, `X` is visible;
- if `P` is today and `viewer` has a post for `P`, `X` is visible;
- if `P` is today and `viewer` has not posted, peer content is hidden, while status and the viewer's own draft remain visible;
- membership in the circle is required in all cases.

This resolves the example in the brief as “history is always readable; only the current day's peer content is gated.”

## Non-goals for MVP

- public discovery, follower counts, comments, reactions, direct messages, rankings, and visible streak leaderboards;
- Android or web clients;
- content editing after submission;
- multiple posts per person per daily prompt;
- background speech recording.

## Success measures

- prompt-to-submission conversion;
- percent of posts submitted inside the ten-minute window;
- notification-to-capture-open latency;
- weekly circle retention;
- failed upload and missed-push rates;
- account deletion completion time.

## Open product decisions

- Whether circle owners or individual members choose the waking window.
- Whether users may belong to multiple active circles in the first release.
- Exact video retention policy and whether originals are downsampled after upload.
- Whether the name “Blessing Circle” is final; trademark and App Store naming checks are required.

