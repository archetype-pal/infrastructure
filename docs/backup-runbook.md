# Database backup & restore runbook

This is the operational contract for the Archetype Postgres database. It
covers what is dumped, where the dumps land, how to verify them, and how
to restore from one — both partially (single table) and fully.

The on-disk Postgres data directory (`postgres:/var/lib/postgresql/data`)
is **not** a backup. Volume corruption, an accidental `docker compose
down -v`, or a host disk failure all destroy it in one step. The logical
dumps produced by the `pg_backup` sidecar are the source of truth for
"can we still recover yesterday's state".

## What's backed up

The `pg_backup` service in `infrastructure/compose.yaml`:

- Reads `DATABASE_URL` from `env_file` (same value the api/celery use).
- Runs `pg_dump` once every 24 hours, gzipped, to `./backups/` on the
  host (bind-mount, host-readable without entering the container).
- Filenames: `local-YYYYMMDDTHHMMSSZ.sql.gz` (UTC, sortable).
- Retention: 14 days; older dumps are deleted on each run.
- Partial writes land at `*.sql.gz.partial` so a half-written file is
  never confused with a real backup. On a clean run it's renamed in
  place; on failure it stays around for an operator to inspect.

Not covered by this runbook (and **not** in the dump):

- Uploaded media under `infrastructure/storage/media/` — those are on
  disk and should be in your nightly filesystem backup story (rsync,
  restic, S3 sync, etc.). The dump knows the rows, but the bytes live
  outside Postgres.
- The Meilisearch index — it's a derived store; rebuild from
  Postgres via `just sync-all-search-indexes` after a restore.
- The Redis broker — task queue; transient by design.

## Off-site copy

The bind-mount keeps backups on the same host as the DB they protect.
For a real DR posture, rsync `./backups/` to off-host storage (S3,
another VPS, an external drive) on a schedule independent of this
sidecar. Suggested cron entry on the host:

```cron
15 4 * * * rsync -a --delete /srv/archetype/infrastructure/backups/ \
            user@offsite:/srv/backups/archetype/
```

Two independent failures (this host AND off-site) are what 14-day
retention is buying you. Don't shrink retention until off-site is in
place.

## Healthcheck: is the sidecar actually running?

```sh
# Last successful dump
ls -lt infrastructure/backups/local-*.sql.gz | head -1

# Sidecar logs (look for the "[pg_backup] OK …" lines)
docker compose logs --tail=20 pg_backup
```

Two failure shapes worth watching for:

- `*.sql.gz.partial` files older than a few minutes — the dump is
  failing partway through (most often: disk space, broken socket to
  Postgres, schema referencing a missing extension).
- No new dump in >25h — sidecar exited or never started. Compose will
  restart it (`restart: unless-stopped`), but a consistently-restarting
  sidecar is a real fault; check `docker compose ps`.

## Restore — full

The procedure assumes you're restoring into the same compose stack and
you accept downtime. For a hot-spare restore, see "Restore to a
parallel database" below.

```sh
# 1. Stop services that write to the DB. Keep postgres running.
docker compose stop api celery

# 2. Drop and recreate the target database.
docker compose exec postgres psql -U postgres -d postgres \
    -c "DROP DATABASE local;"
docker compose exec postgres psql -U postgres -d postgres \
    -c "CREATE DATABASE local OWNER postgres;"

# 3. Restore the dump (replace with the dump you want).
gunzip -c infrastructure/backups/local-20260518T040000Z.sql.gz \
    | docker compose exec -T postgres psql -U postgres -d local

# 4. Bring services back up.
docker compose up -d api celery

# 5. Rebuild the search indexes from the restored DB.
cd ../api && just sync-all-search-indexes
```

The Meilisearch rebuild is required because the indexes will still
reference rows from the pre-restore state.

## Restore — partial (single table)

`pg_dump` produces a plain-text dump (gzipped), so `grep` and friends
work on it. To pull one table:

```sh
gunzip -c infrastructure/backups/local-20260518T040000Z.sql.gz \
    | sed -n '/^COPY public.app_label_modelname /,/^\\.$/p' \
    > restore-modelname.sql
```

…then `psql` that into a scratch database, verify, and `INSERT … SELECT`
back into the live one. Don't `COPY` straight into production unless
you've confirmed there are no FK conflicts with the current state.

## Restore — to a parallel database (zero-downtime check)

Useful when you want to verify a dump WITHOUT touching the live DB:

```sh
docker compose exec postgres psql -U postgres -d postgres \
    -c "CREATE DATABASE local_restore_test;"
gunzip -c infrastructure/backups/local-20260518T040000Z.sql.gz \
    | docker compose exec -T postgres psql -U postgres -d local_restore_test
docker compose exec postgres psql -U postgres -d local_restore_test \
    -c "SELECT count(*) FROM manuscripts_itempart;"
docker compose exec postgres psql -U postgres -d postgres \
    -c "DROP DATABASE local_restore_test;"
```

Do this monthly. A backup that hasn't been restored is a backup you
haven't proved you have.

## Bumping retention

`pg_backup` deletes dumps older than 14 days. Edit the `-mtime +14`
flag in `infrastructure/compose.yaml` to change it. Don't drop below
7 days unless off-site retention covers the difference.

## Manual one-shot dump

```sh
just backup
```

which runs:

```sh
docker compose run --rm pg_backup sh -c \
    'pg_dump "$DATABASE_URL" | gzip > /backups/local-manual-$(date -u +%Y%m%dT%H%M%SZ).sql.gz'
```

Use this before a destructive migration or schema rebase.
