#!/bin/bash
set -e

# Initialize pi agent dir in the container's writable /home/pi
mkdir -p /home/pi/.pi/agent

# Copy read-only configs from mounted /pi-config
if [ -d /pi-config ]; then
  cp -r /pi-config/* /home/pi/.pi/agent/ 2>/dev/null || true
fi

# Ensure the workspace is trusted so extensions/MCP don't prompt.
# The workspace keeps its host path, so the key is whatever the cwd is.
jq -n --arg p "$(pwd)" '{($p): true}' > /home/pi/.pi/agent/trust.json 2>/dev/null || true

exec pi "$@"
