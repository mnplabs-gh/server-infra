#!/usr/bin/env bash
# ==============================================================================
# setup-newrelic.sh - Idempotent New Relic Infrastructure & Logging Provisioning
# Installs newrelic-infra, writes license key, and configures Docker log forwarding.
# Usage: sudo NEW_RELIC_LICENSE_KEY="<key>" ./setup-newrelic.sh
# ==============================================================================

set -euo pipefail

if [ -z "${NEW_RELIC_LICENSE_KEY:-}" ]; then
  echo "::error::NEW_RELIC_LICENSE_KEY environment variable is required."
  exit 1
fi

echo "==> [1/4] Ensuring New Relic repository is configured..."
REPO_FILE="/etc/yum.repos.d/newrelic-infra.repo"
if [ ! -f "$REPO_FILE" ]; then
  curl -fsSL -o "$REPO_FILE" https://download.newrelic.com/infrastructure_agent/linux/yum/el/9/aarch64/newrelic-infra.repo
  echo "    Added New Relic EL9 aarch64 repository."
else
  echo "    New Relic repository already present."
fi

echo "==> [2/4] Installing newrelic-infra package..."
if ! rpm -q newrelic-infra >/dev/null 2>&1; then
  dnf install -y newrelic-infra
  echo "    newrelic-infra installed successfully."
else
  echo "    newrelic-infra is already installed."
fi

echo "==> [3/4] Configuring New Relic license key and logging..."
CONFIG_FILE="/etc/newrelic-infra.yml"
touch "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# Idempotently update or append license_key
if grep -q "^license_key:" "$CONFIG_FILE"; then
  sed -i "s/^license_key:.*/license_key: ${NEW_RELIC_LICENSE_KEY}/" "$CONFIG_FILE"
else
  echo "license_key: ${NEW_RELIC_LICENSE_KEY}" >> "$CONFIG_FILE"
fi

# Set custom display name for host identification
if ! grep -q "^display_name:" "$CONFIG_FILE"; then
  echo "display_name: free-vnic" >> "$CONFIG_FILE"
fi

# Configure Docker container log forwarding via embedded Fluent Bit
LOGGING_DIR="/etc/newrelic-infra/logging.d"
mkdir -p "$LOGGING_DIR"
cat <<'EOF' > "$LOGGING_DIR/docker.yml"
logs:
  - name: docker-containers
    file: /var/lib/docker/containers/*/*.log
EOF

echo "==> [4/4] Starting and enabling newrelic-infra service..."
systemctl daemon-reload
systemctl enable --now newrelic-infra
systemctl restart newrelic-infra

# Wait briefly and verify status
sleep 3
if systemctl is-active --quiet newrelic-infra; then
  echo "==> New Relic Infrastructure agent is active and running!"
else
  echo "::error::newrelic-infra service failed to start."
  systemctl status newrelic-infra --no-pager
  exit 1
fi
