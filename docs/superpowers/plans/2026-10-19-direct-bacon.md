# Direct Bacon participation implementation plan

> **For agentic workers:** Use scoped parallel tasks and verify each interface before integration.

**Goal:** Any first Direct chat/gift can join as Bacon, later valid Roblox names update the same racer, and repeat Follow rewards wait600 seconds.

**Architecture:** TikTok actor IDs remain authoritative. Fallback avatar records explicitly use avatarType=bacon, robloxId=0 and an empty Roblox name; 0 is not an account. Game clones a prepared server template. A later join with avatarUpdate updates only the existing avatar. Independent actors keep their queues and the shared HTTP budget. Follow awards use durable channel/universe/actor cooldown receipts.

**Tech stack:** Existing Node24/SQLite Worker and native Roblox Luau modules.

**Scope:** Direct only; hide Tikkies connection tab. Git push and Studio edits authorized; deployment and publication prohibited.

- [x] Worker RED/GREEN: first arbitrary chat/unmapped gift joins; existing actors do not duplicate; lookup saturation does not block fallback; valid upgrade preserves identity; failed upgrade retains binding; stale/reset/caps safe.
- [x] Follow RED/GREEN: first award,599999ms rejection,600000ms acceptance, reset/reconnect/restart persistence, queue-full rollback, tenant isolation.
- [x] Roblox: cached Bacon template; explicit fallback identity validation; in-place appearance updates with position/rank/timers preserved; no Roblox name on fallback; loading failure keeps running model.
- [x] Public contracts: explicit Bacon0 in overlays/events/TOP WIN only; normal IDs remain strict; no thumbnail network requests for0.
- [x] UI: Direct-only selector and existing Direct help, no Tikkies backend removal.
- [x] Run full Worker suite and native game fixtures, compile modified Studio sources, review changes, sync task-owned workspace files, commit and push only.

Review focus: concurrent duplicate triggers, upgrade while gifts arrive, reset/finish/disconnect during avatar load, per-actor ordering under full lookup capacity, game metadata for avatars without Roblox accounts.
