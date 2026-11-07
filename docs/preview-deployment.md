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

Media is read-only except `uploads/`, so an upload works but a carousel or logo
image does not, and a new upload sits in the folder beta uses. Mail is logged and
not sent.

The encoder and the reader are built on the host and capped at 2 CPUs each. The
letter models are copied to `storage/models/letters`, and must not be published.
After a fresh copy of the database, embed it again:

```sh
docker compose run -d --name ai-embed ai-api sh -c 'for e in hog ink trocr; do
  nice -n 15 python manage.py embed_glyphs --encoder $e || exit 1
done; python manage.py sync_search_index graphs'
```

## Set it up

As root on the host, with the tunnel created beforehand
(`cloudflared tunnel create archetype-ai`, its JSON copied to
`/srv/archetype/cloudflared-ai/credentials.json`, `chown 65532:65532`) and a proxied
CNAME `ai` → `<tunnel id>.cfargotunnel.com` in the `archetype-pal.ink` zone:

```sh
git clone -b ai-programme https://github.com/archetype-pal/infrastructure /srv/archetype/preview
cd /srv/archetype/preview
CLOUDFLARE_TUNNEL_ID=<tunnel id> scripts/preview-init.sh
docker compose build ai-embedder ai-htr
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

The frontend's build fetches `https://ai.archetype-pal.ink/api/v1/` for static
generation and still passes when that does not answer. So publish a new frontend
image once the preview's API is up: an earlier one may hold empty pages.

If beta recreates `image_server`, run `docker compose restart ai-nginx` here. nginx
resolves it only at startup.
