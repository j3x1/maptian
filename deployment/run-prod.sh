#!/bin/bash
set -euo pipefail

# Starts the production Ghost blog container.
#
# IMPORTANT: this must match what is actually running. The container reads its
# port (3711), database and mail settings from a bind-mounted config file that
# lives OUTSIDE the content volume -- without that mount Ghost falls back to
# port 2368 and the port mapping below silently stops working.

CONTAINER=ghost-blog
VOLUME=ghost_content
CONFIG=/root/ghost-config/config.production.json
PORT=3711

# Pinned to the Ghost 5 line on purpose. Do NOT change this to `latest` or
# `ghost:6` without doing a real upgrade -- Ghost applies irreversible database
# migrations on first boot of a new major version. Take a backup first.
IMAGE=ghost:5

if ! docker volume inspect "$VOLUME" > /dev/null 2>&1; then
  echo "Volume '$VOLUME' does not exist. Restore it first (restore-volume.sh)."
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "Config '$CONFIG' not found. Ghost will not start on port $PORT without it."
  exit 1
fi

if docker inspect "$CONTAINER" > /dev/null 2>&1; then
  echo "Container '$CONTAINER' already exists. Remove it first:"
  echo "  docker rm -f $CONTAINER"
  exit 1
fi

docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -e url=https://chaijiaxun.com \
  -e NODE_ENV=production \
  -v "$VOLUME":/var/lib/ghost/content \
  -v "$CONFIG":/var/lib/ghost/config.production.json \
  -p "$PORT":"$PORT" \
  "$IMAGE"

echo "Started $CONTAINER ($IMAGE) on port $PORT"
