#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
command -v node >/dev/null || { echo 'Install Node.js24 LTS first.' >&2; exit 1; }
node -e 'const [major,minor]=process.versions.node.split(".").map(Number);if(major!==24||minor<11){console.error("Requires Node.js24.11+ LTS (major24)");process.exit(1)}'
[[ -f .env ]] || { echo 'Run ./deploy.sh once, then configure .env.' >&2; exit 1; }
node --env-file=.env --input-type=module -e 'import {loadConfig} from "./src/config.mjs";try{loadConfig()}catch(e){console.error(e.message);process.exit(1)}'
mkdir -p data logs
chmod 700 data
chmod 600 .env
if [[ "${1:-}" == '--foreground' ]]; then exec node --env-file=.env src/main.mjs; fi
command -v pm2 >/dev/null || { echo 'Install PM2: npm install -g pm2' >&2; exit 1; }
pm2 startOrRestart ecosystem.config.cjs --update-env
pm2 save
