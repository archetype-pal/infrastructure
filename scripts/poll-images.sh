#!/usr/bin/env bash
# Deploy newly published images. The systemd timer (host/archetype-poll.timer)
# runs this every few minutes on the host; nothing on GitHub's side is involved.
#
# Reads the digests of backend:latest and frontend:beta straight from the
# registry (the packages are public, so an anonymous pull token is enough) and
# hands them to deploy.sh, which pins by digest and takes the deploy lock.
#
# "Newly published" means the tag's digest differs from the one this script
# last saw, not from the pins in .env: a manual rollback to an older image
# therefore stays until the next image is published.
set -euo pipefail
cd "$(dirname "$0")/.."

seen_file=/var/lib/archetype-poll/seen

digest() {
    local image="$1" tag="$2" token
    token="$(curl -fsS --max-time 20 "https://ghcr.io/token?scope=repository:archetype-pal/$image:pull" |
        sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
    curl -fsS --max-time 20 -I -H "Authorization: Bearer $token" \
        -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/archetype-pal/$image/manifests/$tag" |
        tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

backend="ghcr.io/archetype-pal/backend@$(digest backend latest)"
frontend="ghcr.io/archetype-pal/frontend@$(digest frontend beta)"
[[ "$backend" == *@sha256:* && "$frontend" == *@sha256:* ]] ||
    { echo "Could not resolve the image digests from ghcr.io" >&2; exit 1; }

want="$backend $frontend"
if [ -f "$seen_file" ] && [ "$(cat "$seen_file")" = "$want" ]; then
    exit 0 # nothing new published
fi

# Record the images before deploying, so a bad image is tried once, rolled
# back by deploy.sh, and left alone until the next publish.
install -d "$(dirname "$seen_file")"
echo "$want" >"$seen_file"
exec scripts/deploy.sh "$backend" "$frontend" --if-changed
