include env_file
export $(shell sed 's/=.*//' env_file)

build:
	docker compose build
up:
	docker compose up
down:
	docker compose down
up-background:  # bg stands for background
	docker compose up -d
makemigrations:
	docker compose run --rm api python manage.py makemigrations
migrate:
	docker compose run --rm api python manage.py migrate
restart-api:
	docker compose restart api
pytest: export API_ENV_FILE := config/test.env
pytest:
	docker compose run --rm api python -m pytest
shell:
	docker compose run --rm api python manage.py shell_plus
bash:
	docker compose run --rm api bash
update_index:
	docker compose run --rm api python manage.py rebuild_index --noinput
clear_index:
	docker compose run --rm api python manage.py clear_index --noinput
clean:
	poetry run black .
	poetry run isort .
certbot:
	docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $(APP_DOMAIN)
	docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d $(API_DOMAIN)