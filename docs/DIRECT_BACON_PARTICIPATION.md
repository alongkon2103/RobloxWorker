# Direct LIVE: Bacon participation and Follow cooldown

19 October 2026. Source update only; no Worker deployment or Roblox publication performed.

## Behaviour

- The first chat message or any gift creates one Bacon racer using the viewer's stable TikTok user ID. A gift without an effect mapping still joins; it does not invent a gift reward. Likes/follows alone do not create a racer. The existing 100-racer cap remains.
- The nameplate uses the existing filtered TikTok display name/handle pipeline. Bacon has no Roblox username line. The roster and public overlays accept this explicit fallback identity.
- A later valid Roblox username upgrades the existing Bacon's appearance. The Model, actor identity, slot, distance, rank, heart remainder and active effects remain. Loading happens offstage while Bacon keeps running. Failed or stale loads keep Bacon; failed delivery also restores the Worker binding and preserves queued paid effects.
- Name parsing still follows With @ / Without @ / Both. To bound random-name traffic, each Bacon can attempt a Roblox username lookup once per 30 seconds; after a failed lookup, wait 30 seconds and type the correct name again. Four Worker lookups run concurrently globally. Once upgraded, later names do not create another racer.
- Follow grants Fly at most once every 600 seconds for the same TikTok viewer and channel within the Universe. Unfollow/refollow, a new race, reconnect and Worker restart do not bypass this durable cooldown. Another viewer/channel has a separate cooldown. A full queue does not consume the reward or its cooldown.
- This is Direct's fixed Follow rule. This change does not import the Tikkies admin Follow enable/cooldown setting into Direct. Gift mappings still use the session's published snapshot.
- The connection UI shows Direct only. The Tikkies backend/Desktop protocol is unchanged.

## User rollout

1. Back up the existing database and update/deploy the Worker using the normal process with Node 24. Keep its existing SQLite data; two additive tables migrate automatically. No new key or environment variable is required.
2. The current Studio editing copy contains the game changes and `ServerStorage.DirectBaconTemplate`. Save/Publish it when ready, then use a fresh server and reconnect Direct. Updating only the Worker does not install the new game-side Bacon identity support.
3. For a manual script install: add `ViewerAvatar` and `GameEventFeed` beside `GameHandlers` in ServerScriptService; update `GameHandlers`, `RacePresentation`, `OverlayPublisher`, `TopWinResults`. Update `FlyEffects`, `InGameOverlays`, `LiveSettings`, `ViewerRaceHUD` in StarterPlayerScripts and `ViewerFormLifecycle` in ReplicatedStorage. Existing game modules, HTTP budget, access controls and private credentials remain required. If no saved Bacon template exists, `ViewerAvatar` builds and caches one once; concurrent cold joins retry until it is ready.
4. Check a new viewer's arbitrary chat, an unmapped gift, a mapped gift, 20 received viewer likes, Follow, a blocked refollow, and a subsequent valid-name upgrade. Test against the same TikTok account after entry; room-total likes are not viewer rewards.

## Verification

The Worker suite passes 138 tests, including unknown gifts, lookup saturation, identity upgrades, failed/expired joins, queued paid rewards, capacity, cooldown boundaries, reset/reconnect/restart, owner/channel isolation, overlays and TOP WIN. Native Studio fixtures exercise real R15 model replacement and real avatar loading during a moving race: one model remains, distance advances, the slot and Speed Boost/Fly timers remain, and the new rig moves. Separate fixtures cover Fly joint rebinding and active-form nameplate restoration. Changed Studio sources compile.

Production LIVE behaviour after this rollout has not been tested. Provider omissions of per-viewer likes still cannot be reconstructed from room totals.
