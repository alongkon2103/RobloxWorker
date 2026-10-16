const path = require('node:path');
module.exports = {
  apps: [{
    name: 'hyperrun-live-bridge',
    cwd: __dirname,
    script: './src/main.mjs',
    interpreter: 'node',
    node_args: ['--env-file=' + path.join(__dirname, '.env')],
    exec_mode: 'fork',
    instances: 1,
    autorestart: true,
    exp_backoff_restart_delay: 1000,
    max_memory_restart: '512M',
    wait_ready: true,
    listen_timeout: 10000,
    kill_timeout: 12000,
    shutdown_with_message: true,
    merge_logs: true,
    out_file: './logs/output.log',
    error_file: './logs/error.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
    env: { NODE_ENV: 'production' }
  }]
};
