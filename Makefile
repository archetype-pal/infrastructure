include env_file
export

up:
	docker compose up
down:
	docker compose down
shell:
	docker compose run --rm --remove-orphans api python manage.py shell_plus
up-background:
	docker compose up -d
migrate:
	docker compose run --rm api python manage.py migrate
update_index:
	docker compose run --rm api python manage.py setup_search_indexes
postgres-version:
	docker compose exec -T postgres sh -c 'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -c "SHOW server_version;"'
postgres-upgrade-17-to-18:
	./scripts/upgrade-postgres-17-to-18.sh
certbot:
	docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $(DOMAIN)
