#!/usr/bin/env bash
# One-time bootstrap of a fresh Ubuntu host for the tunnel deployment. Run as root:
#   ssh root@HOST 'bash -s' < scripts/bootstrap-host.sh
# Idempotent: safe to re-run.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# SSH: keys only.
cat >/etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sshd -t
systemctl try-reload-or-restart ssh

# Firewall: SSH only. Docker-published ports bypass ufw, so the tunnel stack
# publishes none — cloudflared reaches nginx over the compose network.
ufw allow OpenSSH
ufw --force enable

# Swap as a safety margin for SIPI rendering peaks on small hosts.
if ! swapon --show | grep -q /swapfile; then
    fallocate -l 4G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

apt-get update
apt-get install -y ca-certificates curl git just rsync

# Docker: upstream repo when it already publishes this release, else Ubuntu's packages.
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
if curl -fsI "https://download.docker.com/linux/ubuntu/dists/$codename/Release" >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
        >/etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    apt-get install -y docker.io docker-compose-v2
fi

# Cap container logs so they cannot fill the disk.
if [ ! -f /etc/docker/daemon.json ]; then
    mkdir -p /etc/docker
    echo '{"log-driver": "json-file", "log-opts": {"max-size": "20m", "max-file": "5"}}' >/etc/docker/daemon.json
fi
systemctl enable docker
systemctl restart docker

docker --version
docker compose version
