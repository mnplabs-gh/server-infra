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

# Ensure docker_enabled feature is enabled for container metrics (nri-docker)
if ! grep -q "docker_enabled:" "$CONFIG_FILE"; then
  cat <<'EOF' >> "$CONFIG_FILE"
features:
  docker_enabled: true
EOF
fi

# Configure Docker container log forwarding via embedded Fluent Bit with Lua container name enrichment
INFRA_DIR="/etc/newrelic-infra"
LOGGING_DIR="${INFRA_DIR}/logging.d"
mkdir -p "$LOGGING_DIR"

# Lua script to enrich container logs with human-readable container_name
cat <<'EOF' > "$INFRA_DIR/docker_metadata.lua"
local DOCKER_VAR_DIR = "/var/lib/docker/containers/"
local cache = {}

local function get_container_name_from_disk(container_id)
    local config_file_path = DOCKER_VAR_DIR .. container_id .. "/config.v2.json"
    local file = io.open(config_file_path, "r")
    if not file then return nil end
    local content = file:read("*all")
    file:close()
    local name = content:match('"Name":"/([^"]+)"')
    return name
end

function enrich_with_docker_metadata(tag, timestamp, record)
    local filepath = record["filePath"]
    if not filepath then
        return 0, timestamp, record
    end

    local container_id = filepath:match("/containers/([a-f0-9]+)/")
    if not container_id then
        return 0, timestamp, record
    end

    local container_name = cache[container_id]
    if not container_name then
        container_name = get_container_name_from_disk(container_id)
        if container_name then
            cache[container_id] = container_name
        else
            container_name = "unknown"
        end
    end

    record["container_name"] = container_name
    record["containerName"] = container_name
    record["container_id"] = container_id:sub(1, 12)
    if record["log"] then
        record["message"] = record["log"]
    end

    return 1, timestamp, record
end
EOF

# Fluent Bit configuration using native parser & Lua filter
cat <<'EOF' > "$INFRA_DIR/fluent-bit.conf"
[INPUT]
    Name tail
    Path /var/lib/docker/containers/*/*.log
    Buffer_Max_Size 128k
    Mem_Buf_Limit 16384k
    Skip_Long_Lines On
    Path_Key filePath
    Parser json
    Tag docker-containers
    DB /var/db/newrelic-infra/newrelic-integrations/logging/fb.db
    Read_from_Head true

[FILTER]
    Name lua
    Match docker-containers
    Script /etc/newrelic-infra/docker_metadata.lua
    Call enrich_with_docker_metadata

[FILTER]
    Name record_modifier
    Match docker-containers
    Record hostname free-vnic
    Record plugin.type nri-agent
EOF

# Wire into newrelic-infra logging.d
cat <<'EOF' > "$LOGGING_DIR/docker.yml"
logs:
  - name: docker-containers
    fluentbit:
      config_file: /etc/newrelic-infra/fluent-bit.conf
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
