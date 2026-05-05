# PostgreSQL 18 Upgrade

This infrastructure stack now runs PostgreSQL 18 via `postgres:18.3-bookworm`.

PostgreSQL major versions cannot reuse an older major-version data directory in place. PostgreSQL 18 Docker images also use versioned `PGDATA` under `/var/lib/postgresql/18/docker`, so this Compose file mounts a new `postgres18` volume at `/var/lib/postgresql`.

The old PostgreSQL 17 volume is intentionally left untouched. If an upgrade fails, roll back by pointing the runtime back to the PostgreSQL 17 image and old volume, or restore from the pre-upgrade backup.

## Fresh Server Setup

For a new installation with no existing PostgreSQL 17 volume:

```bash
make up-background
make migrate
make postgres-version
```

`make postgres-version` should report PostgreSQL 18.x.

## Existing PostgreSQL 17 Deployment

Do not start the normal stack against existing PostgreSQL 17 data. Run the upgrade during a maintenance window.

Before upgrading:

1. Confirm the server's real database name, username, and password from `env_file`.
2. Confirm the current volume name. With the default Compose project name it is usually `archetype_postgres`.
3. Take two backups:
   - provider or filesystem snapshot of the current database volume
   - logical dump stored off-host
4. Stop anything that writes to the database.

Then run:

```bash
make postgres-upgrade-17-to-18
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

Backups are written under `backups/postgres-upgrade/<timestamp>/`.

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
make postgres-version
make migrate
docker compose run --rm api python manage.py check
```

Rebuild search indexes if Meilisearch was recreated or search results drift:

```bash
make update_index
```

Rollback rule: never start PostgreSQL 17 on a PostgreSQL 18 data directory.
