# Archetype infrastructure — full-stack Docker Compose orchestration.
#
# Run recipes from this directory, or from elsewhere with:
#   just --justfile infrastructure/justfile --working-directory infrastructure <recipe>
#
# `just` (no recipe) lists everything. Service environment comes from the
# `env_file` in this directory (see .env.prod.sample), which Compose reads via
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

# Collect Django/DRF/admin static assets into STATIC_ROOT. REQUIRED after every
# deploy or image bump — it is not baked into the image, because STATIC_ROOT
# lives under ./storage, which the runtime bind-mount would mask.
#
# Skipping it is not cosmetic: with DEBUG=False the app uses whitenoise's
# CompressedManifestStaticFilesStorage, so any template calling {% static %}
# raises "Missing staticfiles manifest entry" — which means every DRF endpoint
# opened in a BROWSER (Accept: text/html -> the browsable API) returns a hard
# 500, while the same URL fetched with curl returns 200 JSON. Easy to miss.
#
# The api container runs as uid 999, so STATIC_ROOT must be writable by it; the
# recipe creates it 0777 first because the host ./storage is usually owned by a
# different uid.
#
# Collect static assets into STATIC_ROOT (run after every deploy/image bump)
collectstatic:
    mkdir -p storage/staticfiles
    chmod 777 storage/staticfiles
    docker compose exec -T api python manage.py collectstatic --noinput

# Resync every postgres sequence in the public schema to MAX(id) of its owning
# column on the database configured for the Django API. Idempotent. Fixes
# UniqueViolation after explicit-id imports/restores when a sequence drifts
# below MAX(id). Handles both serial and identity sequences.
sync-sequences:
    #!/usr/bin/env bash
    set -euo pipefail
    docker compose run --rm -T api python - <<'PY'
    import os

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

    import django
    from django.db import connection

    django.setup()

    with connection.cursor() as cursor:
        cursor.execute(
            """
            DO $$
            DECLARE r record; mv bigint; has_rows boolean;
            BEGIN
              FOR r IN
                SELECT n.nspname AS schema_name, c.relname AS seq, t.relname AS tbl, a.attname AS col
                FROM pg_class c
                JOIN pg_depend d ON d.objid = c.oid AND d.deptype IN ('a', 'i')
                JOIN pg_class t ON d.refobjid = t.oid
                JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
                JOIN pg_namespace n ON n.oid = c.relnamespace
                WHERE c.relkind = 'S' AND n.nspname = 'public'
              LOOP
                EXECUTE format(
                  'SELECT COALESCE(MAX(%I), 1), MAX(%I) IS NOT NULL FROM %I.%I',
                  r.col, r.col, r.schema_name, r.tbl
                ) INTO mv, has_rows;
                PERFORM setval(format('%I.%I', r.schema_name, r.seq)::regclass, mv, has_rows);
              END LOOP;
            END $$;
            """
        )
    print(f"Synchronized public id sequences for database {connection.settings_dict['NAME']}.")
    PY

# Apply Django database migrations
migrate: sync-sequences
    docker compose run --rm -T api python manage.py migrate

# Open a Django shell_plus in the api container
shell:
    docker compose run --rm --remove-orphans api python manage.py shell_plus

# Open a bash shell in the api container
bash:
    docker compose run --rm api bash

# --- Search (Meilisearch) ----------------------------------------------------

# Create indexes + settings only (no documents)
setup-search-indexes:
    docker compose run --rm -T api python manage.py setup_search_indexes

# Sync every index from the database
sync-all-search-indexes:
    docker compose run --rm -T api python manage.py sync_all_search_indexes

# Sync one index from the DB, e.g. `just sync-search-index item-parts`
sync-search-index INDEX:
    docker compose run --rm -T api python manage.py sync_search_index {{INDEX}}

# Rebuild all search indexes from the DB (schema + documents)
reindex: setup-search-indexes sync-all-search-indexes

# --- Celery ------------------------------------------------------------------

# Inspect active Celery workers
celery_status:
    docker compose run --rm -T api celery -A config inspect active

# --- Database backup / PostgreSQL --------------------------------------------

# Take a one-off gzipped pg_dump into ./backups/ (see docs/backup-runbook.md)
backup:
    docker compose run --rm -T pg_backup sh -c 'pg_dump "$DATABASE_URL" | gzip > /backups/local-manual-$(date -u +%Y%m%dT%H%M%SZ).sql.gz'

# Full restore from a gzipped dump (see docs/backup-runbook.md "Restore — full").
# DESTRUCTIVE: drops and recreates POSTGRES_DB. Stops api/celery during the
# restore and brings them back up after. Usage: just restore backups/local-20260518T040000Z.sql.gz
restore FILE:
    #!/usr/bin/env bash
    set -euo pipefail
    test -f "{{FILE}}" || { echo "No such dump file: {{FILE}}" >&2; exit 1; }
    # POSTGRES_USER/POSTGRES_DB only exist inside the postgres container's own
    # environment (set via compose from env_file) — not in this host shell —
    # so read them back out rather than assuming they're exported here.
    db="$(docker compose exec -T postgres bash -c 'echo -n "$POSTGRES_DB"')"
    read -rp "This will DROP and recreate database '$db'. Continue? [y/N] " confirm
    [[ "$confirm" == "y" || "$confirm" == "Y" ]] || { echo "Aborted."; exit 1; }
    docker compose stop api celery pg_backup
    # DROP DATABASE fails if anything still holds a connection (a lingering
    # `just shell`/`just bash` session, an in-flight pg_backup dump that
    # started before the stop above, etc.) — terminate stragglers first.
    docker compose exec -T postgres bash -c 'psql -U "$POSTGRES_USER" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '"'"'$POSTGRES_DB'"'"' AND pid <> pg_backend_pid();"'
    docker compose exec -T postgres bash -c 'psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE \"$POSTGRES_DB\";"'
    docker compose exec -T postgres bash -c 'psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"'
    # Accept both the sidecar's gzipped dumps and a plain .sql dump (e.g. one
    # produced by `pg_dump` directly, or already decompressed by hand).
    if [[ "{{FILE}}" == *.gz ]]; then
        gunzip -c "{{FILE}}"
    else
        cat "{{FILE}}"
    fi | docker compose exec -T postgres bash -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
    docker compose up -d api celery
    echo "Restore complete. Run 'just reindex' to rebuild search indexes."

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
    docker compose run --rm -T certbot certonly --webroot --webroot-path=/var/www/certbot -d "$domain"
