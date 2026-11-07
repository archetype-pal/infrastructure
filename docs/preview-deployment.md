# The AI preview (ai.archetype-pal.ink)

A build of the AI programme branches, on beta's host, so researchers can try the
AI features on a copy of beta's data. Beta stays on `main`, and its checkout,
nginx and tunnel are not touched.

| | Beta | Preview |
|---|---|---|
| Checkout | `/srv/archetype/infrastructure` | `/srv/archetype/preview` (branch `ai-programme`) |
| Compose project | `archetype` | `archetype-ai` |
| Images | `backend:latest`, `frontend:beta` | `backend:ai-preview`, `frontend:ai-preview` |
| api, workers, frontend, nginx, tunnel | its own | its own, named `ai-*` |
| Postgres | server, database and superuser | same server; database `archetype_ai`, role `ai_preview` |
| Redis | same server, numbers 0 and 1 | numbers 2 and 3 |
| Meilisearch | same server, no prefix | same server, prefix `ai_` |
| SIPI and media | shared | shared; media mounted read-only |

The preview's api and workers join beta's network as `ai-*`. Never name a preview
service as beta names its own: beta's nginx would resolve `api` to both.

Because media is read-only, uploads fail on the preview. Mail is logged and not
sent. Neither the glyph encoder nor the reader runs here: "Letters like this" and
page reading stay off until there is memory for them.

## Set it up

As root on the host, with the tunnel created beforehand
(`cloudflared tunnel create archetype-ai`, its JSON copied to
`/srv/archetype/cloudflared-ai/credentials.json`, `chown 65532:65532`) and a proxied
CNAME `ai` → `<tunnel id>.cfargotunnel.com` in the `archetype-pal.ink` zone:

```sh
git clone -b ai-programme https://github.com/archetype-pal/infrastructure /srv/archetype/preview
cd /srv/archetype/preview
CLOUDFLARE_TUNNEL_ID=<tunnel id> scripts/preview-init.sh
scripts/preview-clone-db.sh
scripts/preview-deploy.sh
install -m 644 host/archetype-ai-poll.* /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now archetype-ai-poll.timer
```

Hosted models answer once `ANTHROPIC_API_KEY=` is added to the preview's `env_file`,
followed by `docker compose up -d`. The site-wide cap is $10 a day.

## Day to day

- **Deploying:** push to backend `ai-programme` or frontend
  `feat/annotation-proposal-queue`. Each publishes its `ai-preview` image, and the
  timer deploys it within minutes. `journalctl -u archetype-ai-poll.service` shows it.
- **A fresh copy of beta's data:** `scripts/preview-clone-db.sh`, then
  `scripts/preview-deploy.sh`. Everything made on the preview is lost.
- **Taking it down:** `docker compose down` in the preview checkout, disable the
  timer, then drop `archetype_ai` and `ai_preview`, and the `ai_*` indexes.

The frontend's first image needs `https://ai.archetype-pal.ink/api/v1/` to answer,
because static generation fetches it. Until then, start the rest with
`docker compose up -d ai-api ai-celery ai-nginx ai-cloudflared` and re-run the workflow.

If beta recreates `image_server`, run `docker compose restart ai-nginx` here. nginx
resolves it only at startup.
