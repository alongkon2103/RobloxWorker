#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
command -v node >/dev/null || { echo 'Install Node.js24 LTS first.' >&2; exit 1; }
if [[ ! -f .env ]]; then
  umask 077
  node --input-type=module <<'JS'
import {readFileSync,writeFileSync} from 'node:fs';
import {randomBytes} from 'node:crypto';
let env=readFileSync('.env.example','utf8');
env=env.replace(/^BRIDGE_API_KEY=$/m,'BRIDGE_API_KEY='+randomBytes(32).toString('hex'));
env=env.replace(/^ADMIN_API_KEY=$/m,'ADMIN_API_KEY='+randomBytes(32).toString('hex'));
writeFileSync('.env',env,{mode:0o600,flag:'wx'});
JS
  echo 'Created .env with separate random bridge/admin keys.'
  echo 'Set EULER_TOKEN in .env, then run ./deploy.sh again.'
  exit 0
fi
node -e 'const [major,minor]=process.versions.node.split(".").map(Number);if(major!==24||minor<11){console.error("Requires Node.js24.11+ LTS (major24)");process.exit(1)}'
node --env-file=.env --input-type=module -e 'import {loadConfig} from "./src/config.mjs";try{loadConfig()}catch(e){console.error(e.message);process.exit(1)}'
node --test test/*.test.mjs
./start.sh
