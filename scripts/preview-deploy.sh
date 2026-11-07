#!/usr/bin/env bash
# Deploy the newest ai-preview images. The timer (host/archetype-ai-poll.timer)
# runs this every few minutes; it does nothing unless a digest changed, or a
# fresh database copy is waiting. Takes beta's deploy lock, so the two never
# restart at once, and touches no container of beta's.
set -euo pipefail
cd "$(dirname "$0")/.."
# Compose would otherwise fall back to compose.yaml, which is project `archetype`.
export COMPOSE_PROJECT_NAME=archetype-ai COMPOSE_FILE=compose.preview.yaml

exec 9>/run/lock/archetype-deploy.lock
flock -w 1800 9 || { echo "A deploy is still running after 30 minutes." >&2; exit 1; }

seen_file=/var/lib/archetype-poll/seen-preview

digest() {
    local image="$1" token
    token="$(curl -fsS --max-time 20 "https://ghcr.io/token?scope=repository:archetype-pal/$image:pull" |
        sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    curl -fsS --max-time 20 -I -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/archetype-pal/$image/manifests/ai-preview" |
        tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

backend="ghcr.io/archetype-pal/backend@$(digest backend)"
frontend="ghcr.io/archetype-pal/frontend@$(digest frontend)"
[[ "$backend" == *@sha256:* && "$frontend" == *@sha256:* ]] ||
    { echo "Could not resolve the ai-preview digests." >&2; exit 1; }

want="$backend $frontend"
if [ -f "$seen_file" ] && [ "$(cat "$seen_file")" = "$want" ]; then
    exit 0
fi
install -d "$(dirname "$seen_file")"
echo "$want" >"$seen_file"

pin() { grep -E "^$1=" .env | tail -n1 | cut -d= -f2-; }
set_pin() { sed -i "s|^$1=.*|$1=$2|" .env; }
prev_backend="$(pin BACKEND_IMAGE)"
prev_frontend="$(pin FRONTEND_IMAGE)"

# nginx.tunnel.conf, pointed at this stack's services, so routes stay in step.
sed -e 's#http://api;#http://ai-api;#' -e 's#http://frontend:3000;#http://ai-frontend:3000;#' \
    nginx.tunnel.conf >nginx.preview.conf

manage() { docker compose run --rm -T ai-api python manage.py "$@" </dev/null; }

deploy() {
    set_pin BACKEND_IMAGE "$backend"
    set_pin FRONTEND_IMAGE "$frontend"
    docker compose pull --quiet --ignore-buildable
    manage migrate --noinput
    docker compose up -d --remove-orphans --wait --wait-timeout 300
    docker compose restart ai-nginx
    docker compose up -d --wait --wait-timeout 120 ai-nginx ai-cloudflared
    docker compose exec -T ai-api python manage.py collectstatic --noinput
    manage setup_search_indexes
    if [ -e storage/.needs-reindex ]; then
        manage sync_all_search_indexes
        # Ask's identity starts absent and off in any database, and beta has none.
        manage agent_identity ask-archetype --create --public-tools --enable
        rm storage/.needs-reindex
    fi
    domain="$(grep -E '^DOMAIN=' env_file | tail -n1 | cut -d= -f2-)"
    for path in /api/v1/version/ /; do
        docker compose exec -T ai-nginx wget -q -O /dev/null --header "Host: $domain" "http://127.0.0.1$path"
    done
}

echo "Deploying backend=$backend frontend=$frontend"
set +e
(set -e; deploy)
status=$?
set -e
if [ "$status" -eq 0 ]; then
    docker image prune -f >/dev/null
    echo "Deploy OK."
    exit 0
fi

# Migrations stay applied: the preview's database is a copy, and can be cloned again.
echo "Deploy failed; restoring the previous images." >&2
set_pin BACKEND_IMAGE "$prev_backend"
set_pin FRONTEND_IMAGE "$prev_frontend"
docker compose up -d --remove-orphans --wait --wait-timeout 300 || true
exit 1
