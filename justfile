# Archetype infrastructure — full-stack Docker Compose orchestration.
#
# Run recipes from this directory, or from elsewhere with:
#   just --justfile infrastructure/justfile --working-directory infrastructure <recipe>
#
# `just` (no recipe) lists everything. Service environment comes from the
# `env_file` in this directory (see env_file.example), which Compose reads via
# each service's `env_file:` directive — so recipes don't need to load it.

set export

# Default recipe: list everything (run `just` with no arguments).
default:
    @just --list

# --- Stack lifecycle ---------------------------------------------------------

# Start the full stack in the foreground
up:
    docker compose up

# Start the full stack detached (background). bg stands for background.
up-bg:
    docker compose up -d

alias up-background := up-bg

# Stop the stack (data/volumes are kept)
down:
    docker compose down --remove-orphans

# Stop the stack AND delete volumes — DESTROYS the database
down-volumes:
    docker compose down -v --remove-orphans

# Restart every service
restart:
    docker compose restart

# Restart only the api container
restart-api:
    docker compose restart api

# Pull the latest published images (api / frontend / …)
pull:
    docker compose pull

# Show service status
ps:
    docker compose ps

# Follow logs for all services (Ctrl-C to stop)
logs:
    docker compose logs -f

# --- Application -------------------------------------------------------------

# Apply Django database migrations
migrate:
    docker compose run --rm api python manage.py migrate

# Open a Django shell_plus in the api container
shell:
    docker compose run --rm --remove-orphans api python manage.py shell_plus

# Open a bash shell in the api container
bash:
    docker compose run --rm api bash

# --- Search (Meilisearch) ----------------------------------------------------

# Create indexes + settings only (no documents)
setup-search-indexes:
    docker compose run --rm api python manage.py setup_search_indexes

# Sync every index from the database
sync-all-search-indexes:
    docker compose run --rm api python manage.py sync_all_search_indexes

# Sync one index from the DB, e.g. `just sync-search-index item-parts`
sync-search-index INDEX:
    docker compose run --rm api python manage.py sync_search_index {{INDEX}}

# Rebuild all search indexes from the DB (schema + documents)
reindex: setup-search-indexes sync-all-search-indexes

# --- Celery ------------------------------------------------------------------

# Inspect active Celery workers
celery_status:
    docker compose run --rm api celery -A config inspect active

# --- Database backup / PostgreSQL --------------------------------------------

# Take a one-off gzipped pg_dump into ./backups/ (see docs/backup-runbook.md)
backup:
    docker compose run --rm pg_backup sh -c 'pg_dump "$DATABASE_URL" | gzip > /backups/local-manual-$(date -u +%Y%m%dT%H%M%SZ).sql.gz'

# Print the running PostgreSQL server version
postgres-version:
    docker compose exec -T postgres bash -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SHOW server_version;"'

# Upgrade an existing PG17 volume to PG18 (see docs/postgresql-18-upgrade.md)
postgres-upgrade-17-to-18:
    ./scripts/upgrade-postgres-17-to-18.sh

# --- TLS / certificates ------------------------------------------------------

# Obtain/renew Let's Encrypt certificates for the DOMAIN set in env_file
certbot:
    #!/usr/bin/env bash
    set -euo pipefail
    domain="$(grep -E '^[[:space:]]*DOMAIN=' env_file | tail -n1 | cut -d= -f2- | tr -d '"' | xargs)"
    test -n "$domain" || { echo "DOMAIN is not set in env_file" >&2; exit 1; }
    docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d "$domain"
