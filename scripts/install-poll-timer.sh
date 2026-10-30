#!/usr/bin/env bash
# Install or refresh the image poll timer on the host. Idempotent; run as root
# from the checkout. The deploy workflow runs it on every push to main, so a
# change to host/ or scripts/poll-images.sh reaches the host with the next deploy.
set -euo pipefail
cd "$(dirname "$0")/.."
install -m 644 host/archetype-poll.service host/archetype-poll.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now --quiet archetype-poll.timer
echo "archetype-poll.timer: $(systemctl is-active archetype-poll.timer)"
