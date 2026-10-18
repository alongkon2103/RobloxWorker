# 100 racers and TikTok names

- Game: 100 viewer NPCs per owner, with a shared hard ceiling of 100 NPCs per Roblox server. These are NPC runners, not Roblox player slots.
- Worker: default 100 actors per stream; settings above 100 clamp to 100. Existing lower `.env` settings remain lower until migrated.
- Atomic Worker and game reservations prevent concurrent joins from accepting the 101st racer. Rejoining an existing actor does not consume another slot.
- Main capsule label: TikTok display nickname from the provider's `user.nickname`, falling back to the TikTok handle if the provider supplies no nickname. Small second label: Roblox username.
- Nicknames are filtered server-side for broadcast before reaching a label or the `ViewerDisplayName` model attribute. Failures show `Viewer`, never unfiltered text.
- Capsule ribbons are inset and shortened so their rotated corners fit inside the rounded body. The rank badge and portrait fit the new two-line layout.

## What creates a racer in Direct LIVE

1. Connect the correct TikTok LIVE and wait for Connected.
2. The viewer sends their actual Roblox **Username** in that LIVE's chat. Both mode accepts `Builderman` and `@Builderman`. Lookup is case-insensitive.
3. The entire comment must be the username, not `Roblox: Builderman`, a link, a TikTok nickname or Roblox Display Name.
4. The account must resolve and its avatar must load. The owner must still be present and the round must accept new racers. Running races support late joins; a Results ceremony does not accept joins.
5. Merely viewing the stream, being the Roblox host, sending a gift, liking or following does not identify which Roblox avatar to use. Those events affect an already joined racer.
6. A new racer is not accepted once capacity is full. Existing actors can rejoin without taking another slot. Resetting the round clears the actor bindings for the new round.

## Deployment

Run `node scripts/set-viewer-capacity.mjs .env` on the VPS to set the existing
`MAX_VIEWERS_PER_STREAM` to 100. The helper preserves other fields and writes a
private backup. Then deploy the Worker. `/healthz` reports `viewerCapacity: 100`.
Publish the Studio changes in RaceConfig, GameHandlers, RacePresentation,
ViewerDisplayName and ViewerRaceHUD.

## Verification

Worker tests cover 100 accepted actors, rejection of 101, 105 concurrent lookups,
rejoining at capacity, nickname transport, join-format rules and env migration.
Studio tested production join logic with stand-in avatar/race services: exactly
100 of 101 concurrent joins were accepted. Real TextService accepted the Thai
nickname preview. Rotated ribbon corners were checked against capsule bounds.
This is a capacity/logic test, not a performance benchmark with 100 live viewers
and 100 fully loaded individual avatars.
