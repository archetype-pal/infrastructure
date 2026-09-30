# Database backup & restore runbook

This is the operational contract for the Archetype Postgres database. It
covers what is dumped, where the dumps land, how to verify them, and how
to restore from one — both partially (single table) and fully.

The on-disk Postgres data directory (the `postgres18` volume, mounted at
`/var/lib/postgresql` with `PGDATA=/var/lib/postgresql/18/docker`)
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
  place.

> **On failure the partial is deleted, not kept.** The service logs
> `[pg_backup] FAILED — leaving .partial for inspection` and then runs
> `rm -f "$out.partial"` on the next line, so the message is wrong and no
> artefact survives. **A failed dump leaves only a log line.** This is a bug in
> `compose.yaml`, not just in this document — see "Known gap" below.

Not covered by this runbook (and **not** in the dump):

- Uploaded media — whatever `MEDIA_HOST_PATH` points at, defaulting to
  `infrastructure/storage/media/`. **Check that variable before writing your
  backup job:** if it aliases an external corpus, uploads land there and the
  in-checkout `storage/media/` is shadowed and empty, so backing up the
  checkout would capture nothing. These bytes are on disk and belong in your
  nightly filesystem backup story (rsync, restic, S3 sync, etc.); the dump
  knows the rows, but not the files. For images uploaded through the
  backoffice the served JP2 is the only copy, so this is the one thing
  standing between a disk failure and losing them. (`storage/uploads_tmp/`
  is transient chunk staging — no backup needed.)
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
ls -lt backups/local-*.sql.gz | head -1

# Sidecar logs (look for the "[pg_backup] OK …" lines)
docker compose logs --tail=20 pg_backup
```

The failure shape to watch for:

- **No new dump in >25h** — the sidecar exited, never started, or is failing
  every cycle. Compose restarts it (`restart: unless-stopped`), but a
  consistently-restarting sidecar is a real fault; check `docker compose ps`.

Age of the newest dump is the *only* reliable signal, because a failing dump
leaves nothing behind but a log line. Grep for the failure directly:

```sh
docker compose logs pg_backup | grep FAILED
```

### Known gap

`compose.yaml`'s failure branch deletes the partial it says it is keeping:

```sh
echo "[pg_backup] FAILED — leaving .partial for inspection" >&2
rm -f "$$out.partial" || true          # ← contradicts the line above
```

Dropping the `rm -f` restores the documented behaviour and gives failures a
durable artefact. It is left as-is pending a decision, because it changes what
accumulates in `./backups/` on a persistently failing sidecar.

## Restore — full

The procedure assumes you're restoring into the same compose stack and
you accept downtime. For a hot-spare restore, see "Restore to a
parallel database" below.

**Run every command from `infrastructure/`.** The paths below are relative to
it, and `docker compose` must resolve *this* stack's `compose.yaml` (project
`archetype`) — see the warning after step 5.

```sh
# 1. Stop services that write to the DB. Keep postgres running.
docker compose stop api celery

# 2. Drop and recreate the target database.
#    -U/-d default to POSTGRES_USER/POSTGRES_DB (postgres/local unless
#    env_file overrides them). Confirm before running against production.
docker compose exec postgres psql -U postgres -d postgres \
    -c "DROP DATABASE local;"
docker compose exec postgres psql -U postgres -d postgres \
    -c "CREATE DATABASE local OWNER postgres;"

# 3. Restore the dump (replace with the dump you want).
gunzip -c backups/local-20260518T040000Z.sql.gz \
    | docker compose exec -T postgres psql -U postgres -d local

# 4. Bring services back up.
docker compose up -d api celery

# 5. Rebuild the search indexes from the restored DB — from HERE, not ../api.
just sync-all-search-indexes
```

The Meilisearch rebuild is required because the indexes will still
reference rows from the pre-restore state.

> **Step 5 previously read `cd ../api && just sync-all-search-indexes`, which
> silently rebuilt the wrong stack.** `api/compose.yaml` is a separate
> dev/CI stack under the compose project `archetype-dev`, with its own
> containers, network and Meilisearch volume. Running its recipe reindexes the
> *development* search engine and leaves production's indexes still pointing at
> pre-restore rows — the exact failure step 5 exists to prevent, and a silent
> one: the command succeeds. `infrastructure/justfile` has its own
> `sync-all-search-indexes`; use that.

## Restore — partial (single table)

`pg_dump` produces a plain-text dump (gzipped), so `grep` and friends
work on it. To pull one table:

```sh
gunzip -c backups/local-20260518T040000Z.sql.gz \
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
gunzip -c backups/local-20260518T040000Z.sql.gz \
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

**Manual dumps are reaped on the same 14-day schedule.** The retention sweep
matches `local-*.sql.gz`, and `local-manual-…` matches it too. If a pre-migration
safety dump needs to outlive two weeks, copy it somewhere outside `./backups/`.
