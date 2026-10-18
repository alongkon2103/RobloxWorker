# Game Events Worker deployment — 18 October 2026

- Repository alongkon2103/RobloxWorker main. Base 4570d8d, deployed code 3a8c040. Fast-forward only; no history rewrite or stash/reset.
- VPS /var/www/RobloxWorker/RobloxWorker. Restarted only PM2 hyperrun-live-bridge, retaining Node24.22.0. Auth/Web not restarted.
- Environment and local interpreter configuration unchanged byte for byte. Existing staged ecosystem.config.cjs override retained intentionally; not committed.
- Private backups: /home/alongkon/worker-game-events-20261018T075522Z (env/config, code, consistent online SQLite with integrity_check=ok, before audit, verification.json).
- Exact release tree passed 90/90 tests with Node24.
- Production: health200, six scoped views map/ranking/speed/topWin/all/events, events HTML200, fingerprinted event-renderer200 with immutable caching, existing read state200, anonymous read401.
- Existing read profiles/tokens unchanged; weekly score row count and sum preserved. No key rotation, schema migration, broadcaster fields or score reassignment.
- No fake production events injected. Publisher offline during verification; real LIVE/gameplay is not claimed tested.
- Studio feed hooks were installed in prior task, not published by this deployment. Tikkies Auth/Desktop updates remain separate pending changes.
- Rollback code using saved archive or Git revert; retain current data/env/Node24, restart only Worker and recheck HTTP/read state. Do not restore old SQLite merely to roll back code.
