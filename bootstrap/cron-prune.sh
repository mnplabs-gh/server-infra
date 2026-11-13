#!/usr/bin/env bash
# ==============================================================================
# cron-prune.sh - Automated Docker Maintenance
# Cleans dangling containers, build cache, and images older than 7 days.
# Safe: Active containers and images in use are NEVER deleted.
# ==============================================================================

set -euo pipefail

LOG_TAG="docker-prune"
logger -t "$LOG_TAG" "Starting scheduled Docker cleanup..."

# 1. Prune dangling build cache
docker builder prune -f --keep-storage 2GB 2>&1 | logger -t "$LOG_TAG" || true

# 2. Prune dangling images (untagged <none> images left after deployments)
docker image prune -f 2>&1 | logger -t "$LOG_TAG" || true

# 3. Prune unused images older than 7 days (168h) to reclaim disk space
docker image prune -a --filter "until=168h" -f 2>&1 | logger -t "$LOG_TAG" || true

logger -t "$LOG_TAG" "Docker cleanup completed. Disk usage:"
docker system df 2>&1 | logger -t "$LOG_TAG" || true
