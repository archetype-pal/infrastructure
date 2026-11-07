#!/usr/bin/env bash
# Replace the preview's database with a copy of beta's. Beta is only read: its
# dump runs in one read-only snapshot, and it keeps serving meanwhile. Everything
# made on the preview is lost, the AI spend ledger included.
#
# The copy belongs to its own role, which cannot read beta's tables.
# Run scripts/preview-deploy.sh next: it migrates and reindexes the copy.
set -euo pipefail
cd "$(dirname "$0")/.."
# Compose would otherwise fall back to compose.yaml, which is project `archetype`.
export COMPOSE_PROJECT_NAME=archetype-ai COMPOSE_FILE=compose.preview.yaml
beta="${BETA_DIR:-/srv/archetype/infrastructure}"
target=archetype_ai
role=ai_preview

exec 9>"${DEPLOY_LOCK:-/run/lock/archetype-deploy.lock}"
flock -w 1800 9 || { echo "A deploy is still running after 30 minutes." >&2; exit 1; }

value() { grep -E "^$2=" "$1" | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
source_db="$(value "$beta/.env" POSTGRES_DB)"
admin="$(value "$beta/.env" POSTGRES_USER)"
password="$(value env_file POSTGRES_PASSWORD)"
[ -n "$source_db" ] && [ -n "$admin" ] && [ -n "$password" ] || { echo "Missing settings in .env or env_file." >&2; exit 1; }
[ "$source_db" != "$target" ] || { echo "Refusing: beta's database is named $target." >&2; exit 1; }

container="$(docker ps -q --filter label=com.docker.compose.project=archetype --filter label=com.docker.compose.service=postgres)"
[ -n "$container" ] || { echo "Beta's postgres is not running." >&2; exit 1; }
sql() { docker exec -i "$container" psql -v ON_ERROR_STOP=1 -q -U "$admin" -d postgres "$@"; }

docker compose stop ai-api ai-celery ai-celery-learn ai-prune 2>/dev/null || true

sql -v role="$role" -v password="$password" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'role') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'role') \gexec
ALTER ROLE :"role" WITH LOGIN PASSWORD :'password';
SQL
sql -c "DROP DATABASE IF EXISTS $target WITH (FORCE)"
sql -c "CREATE DATABASE $target OWNER $role"
docker exec "$container" sh -c "pg_dump -Fc -U '$admin' -d '$source_db' | pg_restore -U '$admin' -d '$target' --no-owner --no-privileges --role='$role' --single-transaction --exit-on-error"

rm -f "${PREVIEW_SEEN_FILE:-/var/lib/archetype-poll/seen-preview}"
touch storage/.needs-reindex
echo "Copied $source_db to $target."
