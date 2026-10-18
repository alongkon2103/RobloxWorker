# TOP WIN and in-game overlays

## Player controls

- Course line and TOP WIN are separate in-game widgets. Drag anywhere on a widget, with mouse or touch.
- Double-click or double-tap to open its size slider (30–180%, limited by viewport size), Hide and Reset size.
- The permanent illustrated OVERLAYS button opens visibility toggles and Reset position and size. It remains available when both widgets are hidden.
- The control menus reuse StreamerUI's illustrated parchment panel and cyan/orange button sprites. Broadcast/course/leaderboard styling stays unchanged.
- TOP WIN height follows the number of rows, up to ten. Empty boards remain compact. The in-game course uses an antialiased image at 3x display resolution; if editable images are unavailable, complete fallback color layers avoid segment seams.
- In-game visibility has no effect on private link publication. Links run automatically; there is no enable/pause control.

## Names and wins

All link race/ranking/speed overlays and TOP WIN use filtered TikTok display nicknames. Missing nicknames fall back to the available TikTok handle through the same filter. Roblox IDs still select avatar portraits. A nickname change keeps the competitor's stable TikTok actor identity.

A first-place finish generates a server-only immutable race ID, after sorting finish times. Waiting, racing leaders and DNF never produce wins. Studio/dev/test races never change production TOP WIN. A win is counted once even when packets retry or name/winner data changes on a repeated packet.

Direct LIVE scores are isolated by universe, Roblox streamer owner and the authenticated TikTok channel name. Tikkies currently supplies no authoritative TikTok channel metadata: its board is isolated by the authenticated Roblox streamer owner. This does not merge two owners, but switching TikTok channels within the same Tikkies owner cannot yet produce separate boards. An upstream metadata contract is documented in TIKKIES_TOP_WIN_METADATA.md.

Weeks start Monday 00:00 Asia/Bangkok. Late delivery uses finish time, not arrival time. Scores and receipt IDs persist in Worker SQLite. Old weeks remain stored; a new week selects an empty bucket. Existing open boards update without a new race. Direct channel/job bindings survive disposable session cleanup so a queued result can arrive up to seven days later.

Roblox retries failed result delivery and saves pending receipts in the HyperRunTopWinOutboxV1 DataStore, reloads them when the owner rejoins and flushes on shutdown. The queue is bounded to 200 pending results per server; Worker outages should still be repaired promptly. No software can guarantee a result if both HTTP and Roblox DataStore fail and the server is immediately lost before either saves it.

## Worker endpoints

Existing read-only URL format stays unchanged. New view: `/overlay?view=top-win#READ_TOKEN`.
Tikkies overlay-links response adds `urls.topWin`; existing map/ranking/speed/all keys remain.
`GET /v1/overlay/state` adds topWin `{title,week,nextResetAt,channel,rows}` independently of the race snapshot.

Map-authenticated server endpoints (never client keys):
- `POST /v1/overlays/top-win/result`: ownerRobloxId, jobId, raceId, actorKey, name, robloxId, provider, channel, finishedAt (Unix milliseconds).
- `POST /v1/overlays/top-win/board`: ownerRobloxId, jobId and optional provider/channel. Omit provider to read the last selected channel offline.

Map keys constrain the universe. Direct channel/job bindings must have existed in an authenticated Worker live session. The legacy globally privileged bridge key remains compatible with legacy links.

## Release

Deploy the updated Worker first; then Publish the saved Studio changes. No new .env fields are required. Existing SQLite database is migrated automatically; preserve it and back it up normally. Production DataStore/API access is required for durable Roblox outbox delivery. Editable-image availability is optional because the course renderer includes a fallback.

Changed Studio sources: TopWinResults, ViewerRace, GameHandlers, TikkiesGames, OverlayPublisher; new ReplicatedStorage.CourseOverlayArt; StarterPlayerScripts.InGameOverlays and OverlayPanel. Preserve current OverlayConfig credentials/settings.

Verification: Worker suite plus authorization/weekly/durability tests; Studio payload checks for test/DNF exclusion; actual finish-order sorting test; compact zero/two-row heights; mouse drag/double-click/slider/hide/restore; illustrated-menu screenshot. No production TikTok broadcast or 100-real-avatar performance benchmark was used as proof.
