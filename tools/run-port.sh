#!/usr/bin/env bash
# Runs the port: the api app on API_PORT (default 8090) and the gate on PORT (default 8080), with one
# deployment key between them. Its data goes in DATA (default .jac/data/api). Stops both on exit.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
api_port="${API_PORT:-8090}"
export JAC_DEPLOY_KEY="${JAC_DEPLOY_KEY:-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')}"
export JAC_API_LISTEN="127.0.0.1:${api_port}"
export JAC_REMOTE_API="http://127.0.0.1:${api_port}"
[ -n "${DATA:-}" ] && export JAC_API_DATA="$DATA"
"$here/dist/api-linux-x86_64" &
api=$!
trap 'kill $api 2>/dev/null' EXIT
for _ in $(seq 100); do
    (exec 3<>"/dev/tcp/127.0.0.1/${api_port}") 2>/dev/null && break
    sleep 0.1
done
"$here/dist/gate-linux-x86_64"
