#!/usr/bin/env bash
# Deploy pinned images on the host, rolling back the pins if the result is unhealthy.
#
#   scripts/deploy.sh BACKEND_IMAGE FRONTEND_IMAGE [--if-changed]
#
# Run from anywhere on the host; it works in the infrastructure checkout. Image
# pins live in .env (compose interpolation), so pin by digest for exact rollback.
# --if-changed exits early when both pins already match (scheduled runs).
set -euo pipefail
cd "$(dirname "$0")/.."

backend="$1"
frontend="$2"
mode="${3:-}"

pin() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2-; }
set_pin() {
    if grep -qE "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >>.env; fi
}

prev_backend="$(pin BACKEND_IMAGE || true)"
prev_frontend="$(pin FRONTEND_IMAGE || true)"

if [ "$mode" = "--if-changed" ] && [ "$backend" = "$prev_backend" ] && [ "$frontend" = "$prev_frontend" ]; then
    echo "Pins unchanged; nothing to deploy."
    exit 0
fi

domain="$(grep -E '^DOMAIN=' env_file | tail -n1 | cut -d= -f2- | tr -d '"')"

smoke() {
    # Through nginx with the public Host header, as Cloudflare sends it.
    for path in /api/v1/version/ /; do
        docker compose exec -T nginx wget -q -O /dev/null --header "Host: $domain" "http://127.0.0.1$path" ||
            { echo "Smoke test failed: $path" >&2; return 1; }
    done
}

deploy() {
    set_pin BACKEND_IMAGE "$1"
    set_pin FRONTEND_IMAGE "$2"
    docker compose pull --quiet api celery frontend
    docker compose up -d --remove-orphans --wait --wait-timeout 300
    just migrate
    just collectstatic
    smoke
}

echo "Deploying backend=$backend frontend=$frontend"
if deploy "$backend" "$frontend"; then
    docker image prune -f >/dev/null
    echo "Deploy OK."
    exit 0
fi

echo "Deploy failed." >&2
if [ -n "$prev_backend" ] && [ -n "$prev_frontend" ]; then
    echo "Rolling back to backend=$prev_backend frontend=$prev_frontend" >&2
    set_pin BACKEND_IMAGE "$prev_backend"
    set_pin FRONTEND_IMAGE "$prev_frontend"
    docker compose up -d --remove-orphans --wait --wait-timeout 300 || true
fi
exit 1
