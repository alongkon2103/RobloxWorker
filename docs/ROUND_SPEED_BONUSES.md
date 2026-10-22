# Round speed bonuses

22 October 2026. Game source update only; no deployment or Roblox Publish.

| Effect | Permanent speed per gift/reward |
| --- | ---: |
| Speed Boost (including the existing 20 received likes/viewer reward) | +2 |
| Speed V1 / rainbow_cat | +1 |
| Rocket | +5 |
| Naruto | +5 |
| Goku | +10 |
| Asta | +20 |

Permanent means until the current race is cleared, not saved across races. Each accepted effect quantity counts; the same delivery receipt cannot grant it twice. Changing Bacon to a Roblox avatar retains the bonus on the same model. These are flat bonuses, added after temporary form multipliers. The existing race movement limit remains.

Speed Boost adds +10 temporarily and +2 permanently: starting at20 gives32 during its initial five seconds, then22. The next reward gives34 then24. Repeated rewards retain the existing timer extension/cap behaviour. Speed Boost's accumulated permanent base is no longer limited to40; the old timed-multiplier mode is still supported for legacy configurations. It remains a passive boost and does not replace active forms. Octopus slowing still applies to the resulting speed; shield and form priority rules remain.

Asta's base temporary multiplier is now22 instead of30. Its existing extra-gift temporary stacking, durations and visual flight settings are unchanged. The six gift amounts are configured with `RoundSpeedPerGift` in ReplicatedStorage.RaceEventConfig.

Heart Me is gift7934. The Admin row shown by the owner (`Heart Me → Fly`) is already the correct mapping. Publish that Admin configuration, allow the Worker's normal defaults refresh, then reconnect Direct LIVE because an existing session keeps its gift-map snapshot. No forced override or special case was added to the Worker. The new regression test passes the published row through validation, Bacon entry, final-combo Fly delivery and deduplication.

The current Studio editing copy has the changes. Save/Publish it when ready and use a new game server. For manual installation update RaceEventConfig, RaceEventStack, GameHandlers and the DevTest UI, preserving private access-control integration. There is no production Worker code change to deploy for these speed rules.

Verification:139 Worker tests passed. Native Studio fixtures verify 20→32→22, repeated rewards, form priority, all six award amounts and combo quantities, duplicate receipts, same-model avatar upgrades and fresh-round reset. Legacy stack/boost fixtures still pass. Changed Studio sources compile. Production LIVE after Publish has not been tested.
