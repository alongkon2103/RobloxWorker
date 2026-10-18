# TikTok overlays and weekly wins

## User requirements

All existing link overlays show TikTok display nicknames instead of Roblox usernames, matching the racer capsule. Add two draggable in-game overlays: the course line with racer positions, without the surrounding broadcast card or top-five table; and a weekly wins leaderboard. Add the weekly wins leaderboard as its own link overlay and include it in All Views. Link overlays run automatically, with no enable/pause button. Existing private links keep working.

Weekly wins are separated by streamer channel. Weeks begin Monday at 00:00 Asia/Bangkok. A win means first actual finish, once per race. Scores survive restarts, disconnection and opening another Roblox room. Nickname changes do not create a new competitor.

## Implementation decisions

Extend the existing Roblox Luau publisher/client and Node/SQLite Worker, with no new service. Use stable TikTok user ID for competitor identity and authenticated streamer scope for channel identity. Keep game/universe isolation. An anonymous test racer does not contribute production wins. A direct channel must be resolved from authenticated bridge state, not a client-submitted channel name. Tikkies sessions use the authenticated streamer identity available from the existing integration; any unavailable identity must be reported explicitly rather than merging unrelated channels.

Roblox remains authoritative for finish order. Emit an immutable race-result ID including job, owner, run and round, at first finish. Deliver through a bounded retryable result queue independent of changing race snapshots. Worker atomically deduplicates result ID and increments the relevant week's score. Use the authoritative finish time to assign the week, including retried results that arrive after Monday. No inferred winner from a ranking snapshot: a leader or DNF is not a win. Record only valid bound TikTok racers.

Store scores and result receipts in SQLite. Weekly reset selects a new week bucket rather than deleting historical scores. Deduplication survives Worker restart. A week boundary refreshes an already-open overlay even with no new finish. The leaderboard displays top ten with nickname and win count; tie order is deterministic. Empty state says no winners this week. Link view remains useful offline for the weekly board.

Display the filtered TikTok nickname; safe Viewer fallback while filtering is pending or fails. Roblox usernames remain internal avatar identity. Do not expose raw external nicknames in Roblox UI. Preserve the existing avatar behavior and visual palette. All ranking, speed, map labels and weekly views use the same name preference.

In-game course UI samples the actual shared route and uses the same normalized projection/colors as the link view. Racer positions update smoothly from server-authoritative distance; marker crowding remains bounded. Weekly UI uses the same heading, colors and row order as its link equivalent. Both overlays belong to the local streamer, support mouse and touch dragging, stay inside viewport bounds and re-clamp on resize. Default placement avoids existing race controls. In-game visibility controls are separate from link publication; turning off a game widget never pauses its link. Position persistence across sessions is outside this request.

Automatically create/publish each owner's overlay profile with existing exclusive leases and retry/backoff. Remove enable/pause from the links panel, preserve link selection and connection status. Return the new weekly URL through both the game panel and Tikkies overlay-links API without breaking existing keys. Existing links remain read-only and credentials remain server-only.

## Verification

Tests cover per-channel/universe isolation, exact-once wins, invalid/unbound winners, concurrency, persistence, Monday Thailand boundaries and delayed delivery. Validate existing overlays and all existing Worker tests. Studio checks cover filtered nicknames, first-finish hook, no DNF/test wins, dragging bounds, narrow viewport, smooth route rendering and offline leaderboard behavior. Inspect live UI screenshots before finishing. A live TikTok production broadcast and 100-real-avatar performance benchmark are not assumed verified by mocked tests.

## Delivery

Save current Studio sources before editing, preserving concurrent changes. Push tested Worker/game sources to GitHub. User deploys VPS and publishes Roblox. Document required deployment and any integration contract additions for Tikkies; do not silently change Tikkies itself.

## Approved follow-up refinements

User named the board TOP WIN, requested full-surface dragging, double-click size slider/hide controls, compact height matching actual rows, and a permanent OVERLAYS visibility/recovery/reset control. User clarified the overlay itself should keep its existing appearance; only popovers and buttons should use illustrated game art. Implemented with existing StreamerUI panel/button sprites.
