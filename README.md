# infrastructure
This repository contains instructions for setting up the Archetype server on your machine.   
Following the instructions require a little bit of a technical background.

**For all instructions, you will require a terminal window open**

## Prerequisites 
- `Xcode Command Line Tools` Required only for mac
  - Open a terminal and run `xcode-select --install`
- `Git`: Install from https://git-scm.com/downloads
- `Docker`: Install from https://docs.docker.com/engine/install/
- `just`: Command runner used for the shortcuts below. Install from https://github.com/casey/just#installation (`brew install just`, `cargo install just`, or a prebuilt binary on Windows). You can also run the underlying `docker compose` commands directly if you'd rather not install it.


## Build frontend

### For local

```bash
cd frontend-folder

docker build   
  --build-arg NEXT_PUBLIC_API_URL=http://localhost:8000   
  --build-arg NEXT_PUBLIC_IIIF_UPSTREAM=http://localhost:3000   
  --build-arg NEXT_PUBLIC_SITE_URL=http://localhost:3000   
  --build-arg CORS_ALLOWED_ORIGINS=http://localhost:3000   
  --build-arg DOCKER_IMAGE_HASH=local-dev     
  -t geourjoa/archetype-frontend:local-latest .


` 
### For Tetras Libre production

cd frontend-folder

docker build   \
  --build-arg NEXT_PUBLIC_API_URL=https://digipal-api.tetras-libre.fr  \
  --build-arg NEXT_PUBLIC_IIIF_UPSTREAM=https://digipal-iiif.tetras-libre.fr/   \
  --build-arg NEXT_PUBLIC_SITE_URL=https://digipal.tetras-libre.fr   \
  --build-arg CORS_ALLOWED_ORIGINS=https://digipal.tetras-libre.fr   \
  --build-arg DOCKER_IMAGE_HASH=local-dev     \
  -t geourjoa/archetype-frontend:prod-latest .
  
docker push geourjoa/archetype-frontend:prod-latest

## Build Backend

### For local

```bash
cd backend-folder

docker build   
  -t geourjoa/archetype-backend:local-latest .


` 
### For Tetras Libre production

cd backend-folder
docker build   \
  -t geourjoa/archetype-backend:prod-latest .
  
docker push geourjoa/archetype-backend:prod-latest


## Steps to deploy 

1. Get a copy of the needed files from github:
    ```bash 
    >>> git clone git@github.com:archetype-pal/infrastructure.git

    # Navigate to the project directory
    >>> cd infrastructure
    ```

2. Adjust the project configuration to suit your needs.  
    Create a new file `.env` and fill it with the required variables. A working example can be found [here](.env.prod.sample) or [here](.env.dev.sample).

    Existing deployments with PostgreSQL 17 data need a one-time database upgrade before starting the normal PostgreSQL 18 stack. Follow [the PostgreSQL 18 upgrade runbook](./docs/postgresql-18-upgrade.md) first.

3. Run the project in the background 
    ```bash
    >>> just up-bg
    ```
4. Run the database migrations
    ```bash
    >>> just migrate
    ```
5. Build the search indexes (creates the Meilisearch schemas and loads documents from the DB)
    ```bash
    >>> just reindex
    ```
6. Open the website in your browser by navigating to `http://localhost`

> Run `just` (or `just --list`) at any time to see every available command.

## Upgrading an existing deployment

The steps above describe a first deployment. To move a running server to a new
release:

```bash
>>> just pull      # fetch the new images
>>> just up-bg
>>> just migrate   # always — a release may add tables or columns
```

That is enough for most releases. **A release that adds or changes search
facets, filters or sort fields additionally needs:**

```bash
>>> just setup-search-indexes
```

Meilisearch applies index *settings* only when they are pushed, so new facets
stay invisible until this runs — the site keeps working, it simply returns no
values for them. Run `just reindex` instead if the shape of the indexed
documents changed too (it does `setup-search-indexes` then reloads every
document).

Releases needing that extra step say so in their notes. The July 2026 TEI
manuscript-descriptions release is one: it adds `material`, `script`,
`deco_type` and `origin_place` facets to the `item-parts` index, and a
`manuscripts` migration for the new description tables.


## troubleshooting
Since this setup process is very delicate, it's important to know how to check the logs.  
Run the following command
```bash
>>> just logs
```
to see a real-time view of the logs across all services. `just ps` shows which
services are up.
