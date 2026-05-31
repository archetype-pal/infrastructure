# Archetype infrastructure — full-stack Docker Compose orchestration.
#
# Run targets from this directory, or from the repo root with
#   make -C infrastructure <target>
#
# `make` (no target) prints the help below. Environment comes from the
# `env_file` in this directory (see env_file.example): it is optional for
# informational targets and required for anything that starts containers.

-include env_file
export

COMPOSE := docker compose

.DEFAULT_GOAL := help

##@ General

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_.-]+:.*##/ { printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Stack lifecycle

.PHONY: up
up: ## Start the full stack in the foreground
	$(COMPOSE) up

.PHONY: up-background
up-background: ## Start the full stack detached (background)
	$(COMPOSE) up -d

# Short alias for up-background (matches the api justfile's `up-bg`).
.PHONY: up-bg
up-bg: up-background

.PHONY: down
down: ## Stop the stack (data/volumes are kept)
	$(COMPOSE) down

.PHONY: down-volumes
down-volumes: ## Stop the stack AND delete volumes — DESTROYS the database
	$(COMPOSE) down -v

.PHONY: restart
restart: ## Restart every service
	$(COMPOSE) restart

.PHONY: restart-api
restart-api: ## Restart only the api container
	$(COMPOSE) restart api

.PHONY: pull
pull: ## Pull the latest published images (api / frontend / …)
	$(COMPOSE) pull

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: logs
logs: ## Follow logs for all services (Ctrl-C to stop)
	$(COMPOSE) logs -f

##@ Application

.PHONY: migrate
migrate: ## Apply Django database migrations
	$(COMPOSE) run --rm api python manage.py migrate

.PHONY: shell
shell: ## Open a Django shell_plus in the api container
	$(COMPOSE) run --rm --remove-orphans api python manage.py shell_plus

.PHONY: bash
bash: ## Open a bash shell in the api container
	$(COMPOSE) run --rm api bash

##@ Search (Meilisearch)

.PHONY: setup-search-indexes
setup-search-indexes: ## Create indexes + settings only (no documents)
	$(COMPOSE) run --rm api python manage.py setup_search_indexes

.PHONY: sync-all-search-indexes
sync-all-search-indexes: ## Sync every index from the database
	$(COMPOSE) run --rm api python manage.py sync_all_search_indexes

.PHONY: sync-search-index
sync-search-index: ## Sync one index from the DB — usage: make sync-search-index INDEX=item-parts
	@test -n "$(INDEX)" || { echo "Usage: make sync-search-index INDEX=<index-name>"; exit 2; }
	$(COMPOSE) run --rm api python manage.py sync_search_index $(INDEX)

.PHONY: reindex
reindex: setup-search-indexes sync-all-search-indexes ## Rebuild all search indexes from the DB (schema + documents)

# Backwards-compatible alias for older docs/tooling. Now performs a full
# rebuild (schema + documents) rather than schema-only, which is what the
# name has always implied.
.PHONY: update_index
update_index: reindex

##@ Celery

.PHONY: celery-status
celery-status: ## Inspect active Celery workers
	$(COMPOSE) run --rm api celery -A config inspect active

##@ Database backup / PostgreSQL

.PHONY: backup
backup: ## Take a one-off gzipped pg_dump into ./backups/ (see docs/backup-runbook.md)
	$(COMPOSE) run --rm pg_backup sh -c 'pg_dump "$$DATABASE_URL" | gzip > /backups/local-manual-$$(date -u +%Y%m%dT%H%M%SZ).sql.gz'

.PHONY: postgres-version
postgres-version: ## Print the running PostgreSQL server version
	$(COMPOSE) exec -T postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -c "SHOW server_version;"'

.PHONY: postgres-upgrade-17-to-18
postgres-upgrade-17-to-18: ## Upgrade an existing PG17 volume to PG18 (see docs/postgresql-18-upgrade.md)
	./scripts/upgrade-postgres-17-to-18.sh

##@ TLS / certificates

.PHONY: certbot
certbot: ## Obtain/renew Let's Encrypt certificates for the configured DOMAIN
	$(COMPOSE) run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $(DOMAIN)
