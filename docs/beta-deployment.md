# Beta deployment (archetype.elghareeb.space)

A single Hetzner CX33 (4 vCPU, 8 GB, Ubuntu) runs the full stack behind a
Cloudflare Tunnel. No web ports are open; SSH is the only inbound service.

| | |
|---|---|
| Host | `root@65.109.239.185` (key-only SSH) |
| Checkout | `/srv/archetype/infrastructure` |
| Media corpus | `/srv/archetype/media` (`MEDIA_HOST_PATH`) |
| Tunnel | `archetype-beta`, credentials in `/srv/archetype/cloudflared/` |
| Compose files | `compose.yaml` + `compose.tunnel.yaml` + `compose.cloudflared.yaml`, selected by `COMPOSE_FILE` in `.env` |

Because `COMPOSE_FILE` lives in `.env`, plain `docker compose …` and every
`just` recipe on the host already use the tunnel overlays.

## How traffic flows

Cloudflare edge → `cloudflared` container (outbound tunnel) → `nginx:80` over
the compose network → api / frontend / SIPI. nginx publishes no host port:
Docker-published ports bypass ufw, so publishing one would expose the stack.

## Continuous deployment

`.github/workflows/deploy-beta.yml` SSHes to the host and runs
`scripts/deploy.sh` with image pins resolved to digests:

- **push to main**: redeploy with this repo's latest config.
- **every 15 minutes**: deploy newly published `backend:latest` /
  `frontend:elghareeb` images; a no-op when the digests are unchanged.
- **manual run**: optionally pass explicit images, which is also how to roll back.

`deploy.sh` pulls, restarts, migrates, collects static, then smoke-tests
through nginx with the public Host header. If any step fails it restores the
previous pins in `.env` and restarts on them.

Secrets: `BETA_SSH_KEY` (a deploy-only key in root's `authorized_keys`) and
`BETA_KNOWN_HOSTS`; variable `BETA_HOST`.

GitHub disables scheduled workflows after 60 days without repository
activity. Re-enable the workflow in the Actions tab if image deploys stop.

The frontend inlines `NEXT_PUBLIC_*` at build time, so this domain has its own
image: the `elghareeb` build in the frontend repo's `cd.yml`.

## Rebuilding the host from scratch

1. `ssh root@HOST 'bash -s' < scripts/bootstrap-host.sh`
2. Clone this repo to `/srv/archetype/infrastructure`.
3. `cloudflared tunnel create <name>` on a machine logged in to Cloudflare; copy
   the credentials JSON to `/srv/archetype/cloudflared/credentials.json` and
   `chown 65532:65532` it (the cloudflared image runs as that uid).
4. Write `env_file` and `.env` (see the keys below) with fresh secrets.
5. Copy media: `rsync -a --partial media/ root@HOST:/srv/archetype/media/`.
6. `docker compose up -d --wait postgres meilisearch redis`, then restore a dump:
   `docker compose exec -T postgres sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --role="$POSTGRES_USER"' < dump`
7. `docker compose up -d --wait`, then `just migrate`, `just collectstatic`,
   `just setup-upload-storage`, `just reindex`.
8. `cloudflared tunnel route dns --overwrite-dns <name> archetype.elghareeb.space`

Gotchas found while building this host:

- `docker compose run` (used by `just migrate`, `just reindex`, …) reads stdin.
  When driving the host with `ssh HOST 'bash -s' < script`, add `</dev/null` to
  each recipe call or the first one swallows the rest of the script.
- Postgres credentials, `MEILI_ENV` and `REDIS_PASSWORD` are compose
  interpolation variables, so they must be in `.env`, not only in `env_file`.
- The api reads `CELERY_BROKER_URL`, `CELERY_RESULT_BACKEND` and `CACHE_URL`
  from `env_file`; their defaults carry no Redis password, so set them there.
- nginx resolves the `api` and `frontend` upstreams once at startup. After any
  command that recreates those containers, restart nginx or it returns 502.
  `scripts/deploy.sh` does this itself.
- Restore a database whose migration history matches `main`. The dev database
  used on 2026-09-14 also carried AI-programme branch migrations: 14 migrations
  main does not have, extra tables, and NOT NULL columns without defaults on
  `manuscripts_itemimage` and `manuscripts_repository`. Reads work, but inserts
  into those tables fail, image uploads included.
- `NEXT_PUBLIC_IIIF_UPSTREAM` is the bare origin, never `…/sipi`. The frontend
  keeps `/sipi` from the API's IIIF URLs when it builds `/iiif-proxy` paths, so
  a `/sipi` upstream doubles the segment and every manuscript image 404s. It is
  baked in at build time, so the fix is in the frontend's `cd.yml`.
- Django serves `/media` only with `DEBUG` on; nginx serves it from the media
  mount instead. Without that, the home-page carousel images 404.
- `SECURE_SSL_REDIRECT=False`: public traffic is always HTTPS at the edge, and
  the frontend's server-side calls to `http://api` must not be redirected.

## Environment keys

`.env`: `COMPOSE_FILE`, `BACKEND_IMAGE`, `FRONTEND_IMAGE`, `MEDIA_HOST_PATH`,
`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `MEILI_ENV`,
`REDIS_PASSWORD`, `CLOUDFLARE_TUNNEL_ID`, `CLOUDFLARE_CREDENTIALS_FILE`.

`env_file`: everything in `env_file.example`, plus `CELERY_BROKER_URL`,
`CELERY_RESULT_BACKEND`, `CACHE_URL`, `SECURE_SSL_REDIRECT=False` and
`INTERNAL_API_URL=http://api`.
