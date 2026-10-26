# PostgreSQL 18 Upgrade

This stack runs PostgreSQL 18 on the Debian *bookworm* base (`POSTGRES_IMAGE`, default set in `compose.yaml`). Stay on bookworm: the data directory's collation was created against glibc 2.36, and the trixie base (2.41) trips a collation-version mismatch that would force a REINDEX.

PostgreSQL major versions cannot reuse an older major-version data directory in place. PostgreSQL 18 Docker images also use versioned `PGDATA` under `/var/lib/postgresql/18/docker`, so this Compose file mounts a new `postgres18` volume at `/var/lib/postgresql`.

The old PostgreSQL 17 volume is intentionally left untouched. If an upgrade fails, roll back by pointing the runtime back to the PostgreSQL 17 image and old volume, or restore from the pre-upgrade backup.

## Fresh Server Setup

A new installation has no PostgreSQL 17 volume and needs nothing from this
page. After the README's steps, `just postgres-version` should report
PostgreSQL 18.x.

## Existing PostgreSQL 17 Deployment

Do not start the normal stack against existing PostgreSQL 17 data. Run the upgrade during a maintenance window.

Before upgrading:

1. Confirm the server's real database name, username, and password in `env_file`. The helper reads `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` and `POSTGRES_IMAGE` from the shell or `env_file`, never from `.env`, and exports them to every `docker compose` call it makes, so they override `.env`. Missing credentials fall back to `postgres` / `password`.
2. Confirm the current volume name. With the default Compose project name it is usually `archetype_postgres`.
3. Take two backups:
   - provider or filesystem snapshot of the current database volume
   - logical dump stored off-host
4. Stop anything that writes to the database.

Then run:

```bash
just postgres-upgrade-17-to-18
```

For non-interactive server runs:

```bash
./scripts/upgrade-postgres-17-to-18.sh --yes
```

The helper:

1. Stops API, Celery, and PostgreSQL Compose services.
2. Starts a temporary PostgreSQL 17 container on the old volume.
3. Dumps every non-template database except the maintenance `postgres` database, unless `POSTGRES_DATABASES` is set.
4. Starts PostgreSQL 18 on the new `archetype_postgres18` volume.
5. Restores the dumps into PostgreSQL 18.
6. Runs `vacuumdb --all --analyze-in-stages`.
7. Runs Django migrations unless `--skip-migrate` is passed.

Backups are written under `backups/postgres-upgrade/<timestamp>/`. The helper refuses to run if the PostgreSQL 18 volume already holds data, so inspect that volume before retrying.

## Useful Overrides

Use these only after confirming the server's actual runtime values:

```bash
POSTGRES_DATABASES=local ./scripts/upgrade-postgres-17-to-18.sh --yes
POSTGRES_DATABASES=local,archive ./scripts/upgrade-postgres-17-to-18.sh --yes
POSTGRES_OLD_VOLUME=archetype_postgres ./scripts/upgrade-postgres-17-to-18.sh --yes
POSTGRES_NEW_VOLUME=archetype_postgres18 ./scripts/upgrade-postgres-17-to-18.sh --yes
```

The example database name in this repo is `local`. Do not assume production uses the same name.

## Verification

After the upgrade:

```bash
just postgres-version
just migrate
docker compose run --rm api python manage.py check
```

Rebuild search indexes if Meilisearch was recreated or search results drift.
This recreates the index schemas and reloads documents from the restored DB:

```bash
just reindex
```

Rollback rule: never start PostgreSQL 17 on a PostgreSQL 18 data directory.
