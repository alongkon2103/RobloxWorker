# Realtime Roblox receiver protocol

Registration accepts an optional, strictly allowlisted capability object:

```json
{"capabilities":{"batchAck":true,"receiptCacheV2":true}}
```

`receiptCacheV2` is stored on `GameServerSession` and defaults to false for existing rows and registrations without the flag. It means the receiver retains completed event IDs through each event's full expiry, including after session-token refresh. A backend restart preserves this agreement.

| Bound receiver | Event lifetime | Receipt lease |
| --- | --- | --- |
| Legacy / no explicit cache capability | 15 seconds, bounded by the current run lease | 5 seconds |
| Explicit `receiptCacheV2: true` | 120 seconds | 20 seconds |

Every enqueue path, including Desktop gifts and tests, uses the bound server's stored capability. Current owner, server, run, generation and license checks remain required. A response advertising batch ACK alone never opts an old receiver into longer delivery lifetimes.

The backend advertises `capabilities.batchAck: true`. Only then does the receiver use `POST /api/games/runtime/server/ack-batch` with `{receipts:[...]}` containing 1–32 existing single-ACK bodies. All receipts are validated and authorized before any delivery mutation; any invalid item rejects the entire batch. The original `/ack` endpoint remains supported. New receivers retry registration without capability fields if an old backend strictly rejects those fields.

The backend also advertises `capabilities.boundedPipeline: true`. Only then does the receiver include an optional integer `limit` from 1 through 32 in poll requests. SQL atomically caps active receipt leases at 32 per server session, including concurrent polls; the receiver independently caps reserved deliveries at 32. Completed receipts coalesce for 50ms before ACK, so a slow avatar join does not delay polling for another viewer. Each actor has one FIFO queue across poll batches. A batch may contain a prefix of ordinary effects for one actor; a join waits for every earlier event, and later events wait for the join's ACK. Any earlier live receipt lease also blocks that actor's suffix. This retains 32-event batching for busy viewers.

Polling checks pending work every 100ms and rotates owners across batches, including when more than 32 owners have queued events. The advisory owner cursor resets after a backend restart; receipt ownership and capability metadata remain durable. A backend without the pipeline capability continues using empty poll bodies and waits for the current batch to finish before polling again. Batch ACK and pipeline capability are independent; single-ACK backends retain the same bounded actor queues when pipeline support is advertised.

Sparse Desktop submissions can flush every 200ms. A two-request upload token bucket replenishes every 375ms to coalesce sustained traffic without exhausting the minute budget in an early burst. A sliding budget limits event requests to 160/minute and ordinary runtime operations to 170/minute, reserving capacity for start/stop/heartbeat through 180 total/minute. The backend retains its 200 authenticated requests/minute ceiling and 1,200 events/minute per run ceiling.

## Rollout

1. Back up the database, apply migration `20261018120000_receiver_receipt_cache_v2`, and regenerate the Prisma client before deploying the backend.
2. Deploy the backend. Existing Roblox servers retain their original 15s/5s protocol and cannot replay a paid gift after their older deduplication cache expires.
3. Publish the map with `LiveHttpBudget` and the updated `TikkiesGames` adapter. New receivers explicitly negotiate the longer lifetime; old servers may remain online safely.
4. Ship the faster Desktop runtime after the backend's 160/minute submission allowance is available. Older Desktop builds continue to work with their slower flush interval.

These instructions describe the protocol and deployment order; local tests do not establish production deployment or real TikTok gameplay verification.
