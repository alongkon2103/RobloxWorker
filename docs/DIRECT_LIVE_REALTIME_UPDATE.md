# Direct LIVE / Tikkies realtime update

18 October 2026. This records local implementation and verification; it does not confirm production deployment.

## Problems corrected

- Ordinary Direct chat used the same one-event delivery queue as rewards. A crowd could delay a valid heart reward beyond its expiry.
- A failed or slow Roblox username lookup held up unrelated racers' hearts and gifts.
- Legacy timed Speed Boost configuration did not record stacks or apply its passive multiplier correctly. The receiver now supports both timed multiplier and additive configurations, preserving the newer Studio settings and the 40-speed cap.
- An idle owner's long poll could delay another owner's completed join and acknowledgements. A yielding avatar join could also stall ready actors in the same LIVE channel.
- Tikkies used one HTTP acknowledgement per event and could poll another batch before the previous one finished. Its per-session backend limit is stricter than Roblox's general external HTTP limit.

## Direct delivery

The Roblox receiver requests up to 32 events per session, with at most 100 events across the job response. It opts into actor queues and preserves order for each viewer while processing independent viewers and owners concurrently. A yielding avatar join blocks only its own viewer. At most eight Direct avatar joins run concurrently across the job, and ready effects continue even when all join slots are occupied. Failed delivery releases the untouched actor batch suffix for prompt retry. Joins remain dependency barriers; retries and reconnects do not grant the same event twice. Older receivers retain their existing session FIFO protocol.

Empty polls can wait up to 10 seconds and wake as soon as committed events become available. This is an idle wait, not a ten-second delivery delay. While another batch or ACK is pending, polling uses a zero wait. The receiver no longer inserts a fixed one-second pause between deliveries.

Only four Roblox username lookups run concurrently in the Worker. Other actors' ready rewards continue while a lookup is unresolved. An actor still waits for its own join or rebind to complete.

## Tikkies delivery

The upgraded backend advertises a bounded pipeline. The adapter can receive and acknowledge other actors while an avatar yields, retaining per-actor order across polls. There are at most 32 outstanding delivery reservations and active server leases. Ready receipts coalesce for 50ms before batch acknowledgement. A single actor can receive a prefix of effects in one batch; a join remains a barrier. Older backends keep the compatible one-batch-at-a-time receiver path. Desktop pacing and the database migration are described in `TIKKIES_REALTIME_PROTOCOL.md`.

## HTTP admission budget

`ServerScriptService.LiveHttpBudget` gates actual request start times and is shared by the Direct receiver, Tikkies adapter and overlay/result transport.

| Traffic | Maximum starts per rolling minute |
| --- | ---: |
| All covered server HTTP | 360 |
| Direct job poll + ACK combined | 210 |
| All Tikkies runtime calls combined | 180 |

The Worker retains its 240/minute job poll/ACK limit; Tikkies retains its 200/minute session limit. Batches improve event throughput without one HTTP call per reward. The remaining Roblox HTTP allowance is reserved for unrelated game services. Scripts that bypass this gate are outside its accounting.

Each Roblox game server has its own budget. Worker connection capacity and the Euler account's allowed concurrent connections still apply across servers; `MAX_LIVE_CONNECTIONS` is configurable and must fit the provider plan.

## Mapping and TikTok limitations

The authenticated production Worker mapping endpoint returned HTTP 200 and the expected eight gift mappings plus `20 Likes / viewer → speed_boost` and `Follow → fly` during the investigation. Gift quantities, final-combo identity, owner/run/generation isolation and per-viewer like remainders remain unchanged. The room's total likes are never credited to a specific racer.

TikTok can omit per-viewer like notifications in large streams. Receiving every physical tap cannot be guaranteed by downstream code. See the provider library's [like-event documentation](https://github.com/zerodytrash/TikTok-Live-Connector#like).

## Install / rollout

1. Update and deploy the Worker normally with Node 24. No new `.env` secrets are required. Keep the existing SQLite database and credentials; inbox schema migration is automatic.
2. Publish the Roblox map after installing the changed modules. The working Studio copy already contains them. `LiveHttpBudget` must be in ServerScriptService before `LiveBridge` and `TikkiesGames` start; `RaceEventStack` belongs in ReplicatedStorage. Existing private credentials stay server-only.
3. Tikkies also has local backend and Desktop changes. Apply its additive Prisma migration and generate the client before backend deployment, then ship the Desktop update. Follow `docs/games-realtime-protocol.md` in the Tikkies project. Old receivers retain their original short delivery lifetime; only an explicit upgraded receiver opts into longer caching.
4. Restart or rejoin the game after publication, reconnect the LIVE session, and verify real incoming hearts, gifts and follows. Local tests and a mapping read are not evidence of the final deployed LIVE path.

## Verification

Worker tests cover crowded chat, 100 actors and 200 heart rewards, fair multiple-owner batches, unresolved lookups, reset, backpressure, durable recovery, final combos, follow deduplication, and long-poll cancellation.

The final Worker suite passes 121 tests. Native Studio fixtures cover per-actor Direct batches, ready effects during a yielding same-channel join, the two-owner idle-poll case, retry suffix release, fake-clock and concurrent HTTP budgets, nickname fallback, Speed Boost stacks/cap/deduplication, and the Tikkies negotiated/legacy protocols. Tikkies backend tests include actual PostgreSQL integration in three timezones and receipt authorization; its Desktop tests use a fake clock for sustained pacing and request limits.
