# Direct LIVE events

Direct event defaults in this version:

| Trigger | Game effect |
| --- | --- |
| Rosa (8913) | Rocket |
| Rose (5655) | Speed V1 / rainbow_cat |
| Perfume (5658) | Naruto |
| Hand Heart (5660) | Goku |
| Hearts (5586) | Asta |
| 20 likes per joined viewer | Speed Boost |
| Follow by a joined viewer | Fly |
| Confetti (5585) | Gojo |
| Doughnut (5879) | Shield |
| Finger Heart (5487) | Octopus |

Gift entries above were checked against the published endpoint on 2026-10-18.
The actual gift map is still frozen from the published version at session creation.
Direct Follow and 20-like rules are game defaults in `src/direct-rules.mjs`;
the current Tikkies published contract exports gifts only. Changing Tikkies
Desktop's own follow/like rules does not change these Direct defaults.

Since the [Direct Bacon update](DIRECT_BACON_PARTICIPATION.md), the first chat or
any gift creates a Bacon racer. A later valid Roblox username upgrades that same
racer. Follow rewards have a durable 600-second viewer/channel cooldown.
Likes use the sender's packet count, never the room total. Each viewer has an
independent remainder. Progress survives Worker restart and resets with the race.
Duplicate social packets are suppressed across race resets for the receipt
retention period (one hour). Follow display keys are recognized separately from
share messages; shares and unrelated social messages have no game effect.
Tikkies-provider sessions keep their existing behavior.

## Validation and deployment

Covered: provider-shaped messages through simulated Euler sockets, durable inbox,
HTTP delivery, owner isolation, gift combo deduplication, heart thresholds,
remainder, restart/reset, queue backpressure and follow/share distinction.
Studio checked separate Rose/Speed V1 and Likes/Speed Boost rows, the Follow/Fly row and bridge dispatch.
A real TikTok LIVE delivery test has not been performed for this version.

Deploy the Worker, publish the updated `LiveSettings` and `DirectGiftIcons`, then
check `/healthz` contains `features.directSocial: true`. That flag confirms the
code version, not a successful TikTok connection. With a viewer already joined,
verify one mapped gift, 20 personal likes and a genuine new Follow reach the
correct racer. The viewer must be able to Follow; an account already following
will not generate a new Follow merely by tapping its existing follow state.

Viewer capacity defaults to 100, with a hard maximum of 100. Migrate older lower
`MAX_VIEWERS_PER_STREAM` values using `scripts/set-viewer-capacity.mjs` before
deploying. Existing connection, queue and provider plan limits still apply.
