#!/bin/bash
set -e

# Initialize pi agent dir in the container's writable /home/pi
mkdir -p /home/pi/.pi/agent

# Copy read-only configs from mounted /pi-config
if [ -d /pi-config ]; then
  cp -r /pi-config/* /home/pi/.pi/agent/ 2>/dev/null || true
fi

# Ensure workspace is trusted so extensions/MCP don't prompt
echo '{"/workspace": true}' > /home/pi/.pi/agent/trust.json 2>/dev/null || true

exec pi "$@"
