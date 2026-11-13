#!/usr/bin/env bash
# ==============================================================================
# setup-host.sh - Idempotent Host Provisioning Script for Oracle VM
# Configures swap, Docker log rotation, shared network, and directory structure.
# Run with: sudo ./setup-host.sh
# ==============================================================================

set -euo pipefail

echo "==> [1/6] Checking Docker installation..."
if ! command -v docker >/dev/null 2>&1; then
  echo "    Docker is not installed. Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
  TARGET_USER="${SUDO_USER:-$USER}"
  usermod -aG docker "$TARGET_USER" || true
  echo "    Docker installed successfully."
else
  echo "    Docker is already installed ($(docker --version 2>/dev/null || echo 'ready'))."
fi

echo "==> [2/6] Checking swap configuration..."
CURRENT_SWAP=$(free -m | awk '/^Swap:/ {print $2}')
if [ "${CURRENT_SWAP:-0}" -lt 2048 ]; then
  echo "    Swap is low (${CURRENT_SWAP}MB). Setting up a 4GB swapfile..."
  SWAPFILE="/swapfile"
  if [ ! -f "$SWAPFILE" ]; then
    fallocate -l 4G "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=4096
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE"
    swapon "$SWAPFILE"
  fi
  if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  fi
  echo "    4GB swap configured."
else
  echo "    Swap is adequate (${CURRENT_SWAP}MB)."
fi

# Ensure low swappiness so swap is only used to prevent OOM panics
CURRENT_SWAPPINESS=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")
if [ "$CURRENT_SWAPPINESS" -ne 10 ]; then
  echo "    Setting vm.swappiness=10 (current: $CURRENT_SWAPPINESS)..."
  sysctl -w vm.swappiness=10
  if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" >> /etc/sysctl.conf
  else
    sed -i 's/^vm\.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
  fi
else
  echo "    vm.swappiness is already set to 10."
fi

echo "==> [3/6] Configuring Docker daemon log rotation..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
mkdir -p /etc/docker
if [ ! -f "$DOCKER_DAEMON_JSON" ]; then
  cat <<'EOF' > "$DOCKER_DAEMON_JSON"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "20m",
    "max-file": "3"
  }
}
EOF
  echo "    Wrote default log rotation limits to $DOCKER_DAEMON_JSON."
  systemctl restart docker || true
else
  echo "    $DOCKER_DAEMON_JSON already exists. Please verify log-opts max-size is set."
fi

echo "==> [4/6] Ensuring shared Docker network (web-gateway) exists..."
if ! docker network inspect web-gateway >/dev/null 2>&1; then
  docker network create web-gateway
  echo "    Created external Docker network: web-gateway"
else
  echo "    Network web-gateway already exists."
fi

echo "==> [5/6] Establishing application directory layout..."
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

mkdir -p "$TARGET_HOME/portfolio"
mkdir -p "$TARGET_HOME/ai-interviewer"
mkdir -p "$TARGET_HOME/server-infra"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/portfolio" "$TARGET_HOME/ai-interviewer" "$TARGET_HOME/server-infra"
echo "    Ensured application directories exist owned by $TARGET_USER."

echo "==> [6/6] SELinux runner context check..."
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
  echo "    SELinux is Enforcing. If runners fail with 203/EXEC, run:"
  echo "    sudo chcon -R -t bin_t $TARGET_HOME/actions-runner-*"
else
  echo "    SELinux is not in Enforcing mode."
fi

echo ""
echo "=============================================================================="
echo " Host setup completed successfully!"
echo " Apps directory: $APPS_ROOT"
echo " Shared Docker network: web-gateway"
echo "=============================================================================="
