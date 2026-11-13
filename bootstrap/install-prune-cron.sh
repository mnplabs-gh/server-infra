#!/usr/bin/env bash
# ==============================================================================
# install-prune-cron.sh - Installs weekly Docker cleanup cron job
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRUNE_SCRIPT="$SCRIPT_DIR/cron-prune.sh"
chmod +x "$PRUNE_SCRIPT"

CRON_CMD="0 4 * * 0 $PRUNE_SCRIPT >/dev/null 2>&1"

# Check if cron job is already installed
if crontab -l 2>/dev/null | grep -Fq "$PRUNE_SCRIPT"; then
  echo "Prune cron job is already installed in crontab."
else
  (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
  echo "Installed Docker prune cron job: runs every Sunday at 04:00 AM."
fi
