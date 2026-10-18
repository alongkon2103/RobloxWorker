# Tikkies metadata for channel-specific TOP WIN

Current compatibility: game scores remain separated by authenticated Roblox streamer owner. No Tikkies change is required to use that board. To separate multiple TikTok channels used by the same owner, the upstream integration must supply authoritative channel identity.

Please add to authenticated game delivery payloads:

- `streamerTikTokUserId`: immutable TikTok user ID of the broadcaster, a string; resolve it server-side from the authenticated live connection.
- `streamerTikTokUsername`: current channel handle, display-only.
- `tiktokDisplayName`: viewer nickname; existing `tiktokUsername` remains the viewer handle and `actorKey` remains the stable viewer identity.

Include broadcaster metadata in registration/presence or a server-signed owner channel-info response, so the game can select the correct weekly board before any new gift/join. Bind it to the delivery ownerRobloxId, universe and live session. Never derive broadcaster identity from a client request or a viewer's comment. Send channel changes explicitly.

Do not change gift/effect mapping, actor keys, receipts, reset behavior or read-token permissions. Existing clients must tolerate the additional fields. Game nickname propagation supports `tiktokDisplayName` already. After the broadcaster metadata is available, update the game/Worker channel-binding adapter to prefer the immutable broadcaster ID and define any migration from current owner-scoped totals; avoid automatically attributing old scores to a guessed channel.
