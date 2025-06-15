include env_file
export $(shell sed 's/=.*//' env_file)

up:
	docker compose up
down:
	docker compose down
up-background:
	docker compose up -d
migrate:
	docker compose run --rm api python manage.py migrate
update_index:
	docker compose run --rm api python manage.py rebuild_index --noinput
clear_index:
	docker compose run --rm api python manage.py clear_index --noinput
certbot:
	docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $(DOMAIN)
