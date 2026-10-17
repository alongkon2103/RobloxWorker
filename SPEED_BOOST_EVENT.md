# Speed Boost event

Event key: `speed_boost`. Each gift multiplies the racer's running speed by 1.5, cumulatively for the current round. With BaseRunSpeed 16: 1 gift = 24, 2 = 36, 3 = 54, 5 = 121.5 studs/s. A multi-gift delivery applies its full count. A duplicate event receipt does not add stacks again. Existing room/actor validation and atomic effect validation remain authoritative.

`ReplicatedStorage.RaceEventConfig.speed_boost` / `roblox/RaceEventConfig.lua` controls `SpeedMultiplier=1.5`, `StackMode="RoundMultiplier"`, `Attribute="SpeedBoost"`, `MaxStacks=32`. The existing game speed cap remains 1500 studs/s. MaxStacks bounds arithmetic for extreme gift counts; the race movement cap applies earlier.

The racer's `SpeedBoostStacks` attribute holds the count. RaceEventStack multiplies the existing temporary event total by `1.5^stacks`. This passive boost does not replace Rocket/Cat/Naruto/Goku/Asta models or create a tier orb. It persists when timed events expire. Normal round reset removes racer models, so new round racers start with zero stacks.

Test with key 6 / Speed Boost in Test, applying only to the viewed racer. Direct/Tikkies mapping should send `effects:[{key:"speed_boost",value:1,count:1}]`; use the real quantity for a combo. No TikTok gift ID has been guessed or assigned. Bind the desired gift to this event key in your mapping. The API validators accept the new effect without changing existing effect permissions.

Verification: failing pre-implementation check reproduced missing persistent stacking. Pure Luau tests pass for repeated stacks, timed-event composition/expiry, finite huge batches and fresh-racer reset. Server integration passes count accumulation, duplicate receipt, other-racer isolation and no partial application of invalid effect batches. Play verified 5 stacks at 121.5 studs/s and 1 stack at 24, and Test key 6 invokes the event. API suite: 25/25 passing with Node 24. Real TikTok/Tikkies gift delivery was not invoked during the test.
