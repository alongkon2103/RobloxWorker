# Events for the viewed LIVE racer

20 October 2026. Game-only change; no Worker or Tikkies protocol update is needed.

Use the existing Test page or its existing number shortcuts while following a racer. The selected racer may be a LIVE Bacon, a LIVE Roblox avatar, or a Dev racer. In Free Cam the existing centre-of-screen targeting remains. The target card shows the filtered TikTok name and updates the portrait when the same racer upgrades its avatar.

`GameHandlers.devEvent` now resolves the actor inside the caller's current server-held arena instead of requiring a Dev session. The server derives Roblox ID, avatar type, run, generation and viewer metadata from that entry. Existing access controls, request cooldown, event allowlist and normal effect application remain in force. Missing, dead and stale actors cannot receive these events. Normal attack/random-target rules remain unchanged (for example Octopus still selects its target according to its existing rule).

These are manual game grants, not TikTok gifts or follows. They do not send simulated provider events to the Worker or change its heart counters or Follow cooldown. The add-test-racer restriction during an active LIVE room remains.

The current Studio editing copy has targeted updates to `ServerScriptService.GameHandlers` and `StarterPlayerScripts.DevTest`, preserving its private access integration and existing client request queue. The repository also includes the existing `DevTestRequestQueue` dependency for ReplicatedStorage. Publish/save the game when ready; this task does not deploy or Publish it.

Manual native test: run `ViewedRacerEvents.spec.lua` in Studio Play. It uses isolated handler/race clones, replaces whitelist checks only in those clones, tests LIVE Bacon/Roblox and existing Dev racers, and rejects disabled testing, missing/foreign actors, invalid effects, stale/dead racers and removed rounds. Production whitelist code is untouched.
