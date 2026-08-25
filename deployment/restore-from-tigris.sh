#!/bin/bash
set -euo pipefail

# Restores the Ghost blog from a Tigris backup made by backup-to-tigris.sh.
#
#   ./restore-from-tigris.sh --list                 # what is in the bucket
#   ./restore-from-tigris.sh daily/2026-08-26       # restore that snapshot
#   ./restore-from-tigris.sh weekly/2026-08-24
#   ./restore-from-tigris.sh daily/2026-08-26 --db-only
#
# A restore is two halves, because a backup is two halves:
#
#   1. the snapshot tarball  -> database, settings, themes, redirects
#   2. the image mirror      -> content/images
#
# The images are pulled with `rclone copy`, which only fetches what is missing
# locally. On a same-box restore that is usually nothing; on a fresh server it
# is the full ~317 MB.
#
# Ghost is stopped for the duration and started again at the end.

ENV_FILE=${ENV_FILE:-/root/ghost-config/backup.env}
VOLUME_DATA=${VOLUME_DATA:-/var/lib/docker/volumes/ghost_content/_data}
CONTAINER=${CONTAINER:-ghost-blog}
REMOTE=tigris

log()  { echo "[$(date -Is)] $*"; }
fail() { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || fail "config not found at $ENV_FILE"
set -a; . "$ENV_FILE"; set +a

: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET not set}"
: "${BACKUP_S3_ACCESS_KEY_ID:?BACKUP_S3_ACCESS_KEY_ID not set}"
: "${BACKUP_S3_SECRET_ACCESS_KEY:?BACKUP_S3_SECRET_ACCESS_KEY not set}"

PREFIX=${BACKUP_S3_PREFIX-ghost/}
PREFIX=${PREFIX#/}
[ -n "$PREFIX" ] && PREFIX="${PREFIX%/}/"

export RCLONE_CONFIG_TIGRIS_TYPE=s3
export RCLONE_CONFIG_TIGRIS_PROVIDER=Other
export RCLONE_CONFIG_TIGRIS_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY_ID"
export RCLONE_CONFIG_TIGRIS_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_TIGRIS_ENDPOINT="${BACKUP_S3_ENDPOINT:-https://t3.storage.dev}"
export RCLONE_CONFIG_TIGRIS_REGION="${BACKUP_S3_REGION:-auto}"
export RCLONE_S3_DISABLE_CHECKSUM=true

BUCKET="${REMOTE}:${BACKUP_S3_BUCKET}"

if [ "${1:-}" = "--list" ] || [ -z "${1:-}" ]; then
  echo "Weekly snapshots (kept forever):"
  rclone lsl "$BUCKET/${PREFIX}weekly/" 2>/dev/null | awk '{printf "  weekly/%s  %s\n", substr($4,1,10), $1}' | sort -r || echo "  (none)"
  echo
  echo "Daily snapshots:"
  rclone lsl "$BUCKET/${PREFIX}daily/" 2>/dev/null | awk '{printf "  daily/%s  %s\n", substr($4,1,10), $1}' | sort -r || echo "  (none)"
  echo
  images=$(rclone size "$BUCKET/${PREFIX}images" 2>/dev/null | tail -2 | tr '\n' ' ' || true)
  echo "Image mirror: ${images:-(none)}"
  [ "${1:-}" = "--list" ] && exit 0
  echo
  fail "no snapshot given. Pass one of the keys above, e.g. weekly/2026-08-24"
fi

SNAPSHOT=$1
DB_ONLY=false
[ "${2:-}" = "--db-only" ] && DB_ONLY=true

case "$SNAPSHOT" in
  daily/*|weekly/*) ;;
  *) fail "snapshot must look like daily/YYYY-MM-DD or weekly/YYYY-MM-DD" ;;
esac

KEY="${PREFIX}${SNAPSHOT}.tar.gz"
rclone lsf "$BUCKET/$KEY" >/dev/null 2>&1 || fail "$KEY not found in the bucket"

echo
echo "  Restore $SNAPSHOT into $VOLUME_DATA"
echo "  This REPLACES the live database, settings and themes."
$DB_ONLY && echo "  --db-only: the image mirror will NOT be pulled." \
         || echo "  Missing images will be pulled from the mirror."
echo
read -p "Proceed? (y/n) " -n 1 -r; echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "Cancelled"; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

log "downloading $KEY"
rclone copyto "$BUCKET/$KEY" "$WORK/snapshot.tar.gz"

log "extracting"
mkdir -p "$WORK/stage"
tar xzf "$WORK/snapshot.tar.gz" -C "$WORK/stage"

[ -f "$WORK/stage/data/ghost.db" ] || fail "snapshot has no data/ghost.db -- refusing to restore"

log "verifying the snapshot database before touching anything live"
result=$(sqlite3 "$WORK/stage/data/ghost.db" "PRAGMA integrity_check")
[ "$result" = "ok" ] || fail "downloaded database FAILED integrity check: $result"

was_running=false
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]; then
  was_running=true
  log "stopping $CONTAINER"
  docker stop "$CONTAINER" >/dev/null
fi

# Keep what we are about to overwrite, in case this restore is itself a mistake.
SAFETY="/root/backups/pre-restore-$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$SAFETY"
log "saving current data/ settings/ themes/ to $SAFETY"
for dir in data settings themes; do
  [ -d "$VOLUME_DATA/$dir" ] && cp -a "$VOLUME_DATA/$dir" "$SAFETY/"
done

log "restoring database, settings and themes"
for dir in data settings themes; do
  [ -d "$WORK/stage/$dir" ] || continue
  rm -rf "${VOLUME_DATA:?}/$dir"
  cp -a "$WORK/stage/$dir" "$VOLUME_DATA/$dir"
done

if ! $DB_ONLY; then
  log "pulling any missing images from the mirror"
  mkdir -p "$VOLUME_DATA/images"
  rclone copy "$BUCKET/${PREFIX}images" "$VOLUME_DATA/images" \
    --transfers 4 --stats-one-line --stats 0
fi

log "fixing ownership (Ghost runs as uid 1000)"
chown -R 1000:1000 "$VOLUME_DATA"

if $was_running; then
  log "starting $CONTAINER"
  docker start "$CONTAINER" >/dev/null
fi

log "restore complete. Previous data kept at $SAFETY"
