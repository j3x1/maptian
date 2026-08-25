#!/bin/bash
set -euo pipefail

# Deploys the maptian theme from this repo to the live blog.
#
# Run this from your laptop, in the repo root:
#   ./deployment/deploy-theme.sh
#
# It rsyncs the theme into the ghost_content volume and restarts Ghost, which is
# required for .hbs changes to be picked up (Ghost compiles templates at boot)
# and for the ?v= asset hash to change so browsers pull fresh CSS.

REMOTE=${REMOTE:-root@chaijiaxun.com}
CONTAINER=${CONTAINER:-ghost-blog}
THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/maptian"
REMOTE_THEME=/var/lib/docker/volumes/ghost_content/_data/themes/maptian

if [ ! -f "$THEME_DIR/package.json" ]; then
  echo "Theme not found at $THEME_DIR"
  exit 1
fi

echo "==> Validating theme with gscan"
npx --yes gscan@latest "$THEME_DIR" || {
  echo "gscan reported errors. Fix them before deploying."
  exit 1
}

echo "==> Syncing $THEME_DIR -> $REMOTE:$REMOTE_THEME"
rsync -az --delete \
  --exclude '.DS_Store' \
  --exclude '*.zip' \
  --exclude '.vscode' \
  "$THEME_DIR/" "$REMOTE:$REMOTE_THEME/"

echo "==> Fixing ownership (Ghost runs as uid 1000)"
ssh "$REMOTE" "chown -R 1000:1000 $REMOTE_THEME"

echo "==> Restarting $CONTAINER"
ssh "$REMOTE" "docker restart $CONTAINER"

echo "==> Waiting for Ghost to come back"
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' https://chaijiaxun.com/ || true)
  if [ "$code" = "200" ]; then
    echo "Ghost is up (HTTP 200)"
    exit 0
  fi
  sleep 2
done

echo "Ghost did not return 200 within 60s. Check: ssh $REMOTE docker logs --tail 50 $CONTAINER"
exit 1
