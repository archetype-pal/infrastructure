#!/usr/bin/env bash
# Write the preview's .env and env_file from beta's, once. Run as root in the
# preview checkout. Nothing is printed, and beta is only read.
#
#   CLOUDFLARE_TUNNEL_ID=<id> scripts/preview-init.sh
#
# The tunnel's credentials go in /srv/archetype/cloudflared-ai/credentials.json.
set -euo pipefail
cd "$(dirname "$0")/.."
beta="${BETA_DIR:-/srv/archetype/infrastructure}"
host="${PREVIEW_HOST:-ai.archetype-pal.ink}"

[ "$(realpath .)" != "$(realpath "$beta")" ] || { echo "Run this in the preview checkout, not beta's." >&2; exit 1; }
[ ! -e env_file ] || { echo "env_file exists; delete it first to write a new one." >&2; exit 1; }
: "${CLOUDFLARE_TUNNEL_ID:?set CLOUDFLARE_TUNNEL_ID}"

value() { grep -E "^$2=" "$1" | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
redis_password="$(value "$beta/.env" REDIS_PASSWORD)"
db_password="$(openssl rand -hex 24)"
secret_key="$(openssl rand -hex 48)"

umask 077
cat >.env <<ENV
COMPOSE_PROJECT_NAME=archetype-ai
COMPOSE_FILE=compose.preview.yaml
BACKEND_IMAGE=ghcr.io/archetype-pal/backend:ai-preview
FRONTEND_IMAGE=ghcr.io/archetype-pal/frontend:ai-preview
MEDIA_HOST_PATH=$(value "$beta/.env" MEDIA_HOST_PATH)
CLOUDFLARE_TUNNEL_ID=$CLOUDFLARE_TUNNEL_ID
CLOUDFLARE_CREDENTIALS_FILE=/srv/archetype/cloudflared-ai/credentials.json
ENV

# Beta's settings, less anything naming beta, and less mail: the database is a
# copy of real accounts, and a preview should never write to them. Unset, the
# backend logs mail to the console.
grep -vE '^(SECRET_KEY|DEBUG|DATABASE_URL|POSTGRES_|DOMAIN|ALLOWED_HOSTS|CORS_|CSRF_|IIIF_HOST|FRONTEND_URL|NEXT_PUBLIC_|CELERY_|CACHE_URL|EMAIL_|DEFAULT_FROM_EMAIL|SERVER_EMAIL|SENTRY|MEILISEARCH_INDEX_PREFIX|ML_|ANTHROPIC_|LEARN_|INTERNAL_API_URL|SECURE_SSL_REDIRECT)' \
    "$beta/env_file" >env_file
cat >>env_file <<ENV

# --- The preview ---
SECRET_KEY="$secret_key"
DEBUG=False
DOMAIN=$host
ALLOWED_HOSTS=$host,ai-api
CORS_ALLOWED_ORIGINS=https://$host
CSRF_TRUSTED_ORIGINS=https://$host
FRONTEND_URL=https://$host
IIIF_HOST=https://$host/sipi
INTERNAL_API_URL=http://ai-api
SECURE_SSL_REDIRECT=False
POSTGRES_DB=archetype_ai
POSTGRES_USER=ai_preview
POSTGRES_PASSWORD=$db_password
DATABASE_URL=postgresql://ai_preview:$db_password@postgres:5432/archetype_ai
MEILISEARCH_INDEX_PREFIX=ai_
# Beta's redis keeps 0 and 1.
CELERY_BROKER_URL=redis://:$redis_password@redis:6379/2
CELERY_RESULT_BACKEND=redis://:$redis_password@redis:6379/2
CACHE_URL=redis://:$redis_password@redis:6379/3
# Hosted models, with the backend's \$10 daily cap. They stay refused until
# ANTHROPIC_API_KEY is added here.
ML_INFERENCE_ENABLED=true
ML_HOSTED_PROVIDERS_ENABLED=true
ML_AGENT_PROVIDER=claude
ML_DAILY_COST_CAP_MICROS=10000000
ENV
# The umask above is for the two secret files; the containers must traverse storage.
umask 022
mkdir -p storage/staticfiles storage/learn storage/uploads_tmp
chmod 777 storage/staticfiles storage/learn storage/uploads_tmp
echo "Wrote .env and env_file."
