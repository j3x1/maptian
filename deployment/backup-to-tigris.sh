#!/bin/bash
set -euo pipefail

# Backs a Ghost blog up to Tigris (S3-compatible object storage).
#
# Runs ON THE SERVER, from cron. Safe to run more than once a day.
# One script, one site per invocation:
#
#   ./backup-to-tigris.sh chaijiaxun
#   ./backup-to-tigris.sh travellingdevman --check
#   ./backup-to-tigris.sh chaijiaxun --dry-run
#
# ---------------------------------------------------------------------------
# CONFIG
#
#   /root/ghost-config/backup.env          shared: credentials, bucket, endpoint
#   /root/ghost-config/backup.<site>.env   per-site: container, volume, prefix
#
# The site file is loaded second and wins. Everything is namespaced by <site>:
# the key prefix, the lock file and the log lines, so two sites can never write
# to each other's objects or block each other.
#
# ---------------------------------------------------------------------------
# WHAT GETS STORED, AND WHY IT IS SPLIT IN TWO
#
#   <prefix>daily/YYYY-MM-DD.tar.gz    database + settings + themes + redirects
#   <prefix>weekly/YYYY-MM-DD.tar.gz   one per ISO week, kept forever
#   <prefix>images/...                 mirror of content/images, upload-only
#
# For chaijiaxun the database is ~3 MB and changes constantly while the images
# are ~317 MB and are immutable -- Ghost writes content/images/YYYY/MM/file.png
# once and never touches it again. Rolling both into one tarball would mean
# re-uploading the same 317 MB every week forever, ~16 GB/year of near-identical
# copies. Splitting them means each image is stored exactly once and kept
# forever, while the part that actually changes gets real point-in-time
# snapshots. Restoring needs both halves -- see restore-from-tigris.sh.
#
# Logs are deliberately excluded. They are not content, and on chaijiaxun they
# are 126 MB of noise.
#
# ---------------------------------------------------------------------------
# THE INVARIANT EVERYTHING RESTS ON
#
# EVERY OBJECT KEY IS A PURE FUNCTION OF (site, backup date). Re-running a day
# is an idempotent overwrite, never a duplicate, which is what makes "upload
# succeeded but the script died before pruning" a recoverable state rather than
# a mess. Do not add a timestamp, run id or random suffix to these keys.

usage() {
  cat >&2 <<'EOF'
Usage: backup-to-tigris.sh <site> [--check | --dry-run]

  <site>       config suffix, e.g. chaijiaxun or travellingdevman
  --check      validate config and bucket access, upload nothing
  --dry-run    do everything except write to the bucket
EOF
  exit "${1:-1}"
}

SITE=${1:-}
[ -n "$SITE" ] || usage 1
case "$SITE" in
  -h|--help) usage 0 ;;
  -*) echo "Site name must come first." >&2; usage 1 ;;
esac
# Used in file paths and object keys, so keep it boring.
[[ "$SITE" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "Invalid site name: $SITE" >&2; usage 1; }

MODE=run
case "${2:-}" in
  --check)   MODE=check ;;
  --dry-run) MODE=dryrun ;;
  "")        ;;
  *)         echo "Unknown argument: $2" >&2; usage 1 ;;
esac

CONFIG_DIR=${CONFIG_DIR:-/root/ghost-config}
SHARED_ENV="$CONFIG_DIR/backup.env"
SITE_ENV="$CONFIG_DIR/backup.$SITE.env"
REMOTE=tigris

log()  { echo "[$(date -Is)] [$SITE] $*"; }
fail() { echo "[$(date -Is)] [$SITE] ERROR: $*" >&2; exit 1; }

# Refuse to read a credentials file the whole box can see.
require_private() {
  local f=$1 perms
  [ -f "$f" ] || fail "config not found at $f (see config/backup.env.example in the repo)"
  perms=$(stat -c '%a' "$f")
  case "$perms" in
    600|400) ;;
    *) fail "$f is mode $perms; it holds credentials. Run: chmod 600 $f" ;;
  esac
}

require_private "$SHARED_ENV"
set -a
# shellcheck disable=SC1090
. "$SHARED_ENV"
[ -f "$SITE_ENV" ] || fail "site config not found at $SITE_ENV"
# shellcheck disable=SC1090
. "$SITE_ENV"
set +a

: "${BACKUP_S3_BUCKET:?BACKUP_S3_BUCKET not set in $SHARED_ENV}"
: "${BACKUP_S3_ACCESS_KEY_ID:?BACKUP_S3_ACCESS_KEY_ID not set in $SHARED_ENV}"
: "${BACKUP_S3_SECRET_ACCESS_KEY:?BACKUP_S3_SECRET_ACCESS_KEY not set in $SHARED_ENV}"
: "${GHOST_VOLUME:?GHOST_VOLUME not set in $SITE_ENV}"

BACKUP_S3_ENDPOINT=${BACKUP_S3_ENDPOINT:-https://t3.storage.dev}
BACKUP_S3_REGION=${BACKUP_S3_REGION:-auto}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}

VOLUME_DATA=${GHOST_VOLUME_DATA:-/var/lib/docker/volumes/$GHOST_VOLUME/_data}

# Namespaced by site so two blogs can never collide in one bucket.
PREFIX=${BACKUP_S3_PREFIX-$SITE/}
PREFIX=${PREFIX#/}
[ -n "$PREFIX" ] && PREFIX="${PREFIX%/}/"

[ "$BACKUP_RETENTION_DAYS" -ge 2 ] 2>/dev/null \
  || fail "BACKUP_RETENTION_DAYS must be an integer >= 2 (got '$BACKUP_RETENTION_DAYS')"

command -v rclone  >/dev/null || fail "rclone is not installed. apt-get install -y rclone"
command -v sqlite3 >/dev/null || fail "sqlite3 is not installed. apt-get install -y sqlite3"

# rclone is configured entirely through the environment so no credentials are
# ever written to an rclone.conf on disk.
export RCLONE_CONFIG_TIGRIS_TYPE=s3
export RCLONE_CONFIG_TIGRIS_PROVIDER=Other
export RCLONE_CONFIG_TIGRIS_ACCESS_KEY_ID="$BACKUP_S3_ACCESS_KEY_ID"
export RCLONE_CONFIG_TIGRIS_SECRET_ACCESS_KEY="$BACKUP_S3_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_TIGRIS_ENDPOINT="$BACKUP_S3_ENDPOINT"
export RCLONE_CONFIG_TIGRIS_REGION="$BACKUP_S3_REGION"
# Tigris has historically choked on the CRC32 trailers rclone and the AWS SDK
# attach by default. Mirrors BACKUP_S3_CHECKSUM_MODE=when_required elsewhere.
export RCLONE_S3_DISABLE_CHECKSUM=true

BUCKET="${REMOTE}:${BACKUP_S3_BUCKET}"

# --- dates -----------------------------------------------------------------
# UTC throughout. A backup that changes its mind about what day it is at a DST
# boundary would write two keys for one day, or none.

TODAY=$(date -u +%F)
DOW=$(date -u -d "$TODAY" +%u)                                  # 1=Mon..7=Sun
WEEK_MONDAY=$(date -u -d "$TODAY - $((DOW - 1)) days" +%F)
WEEK_SUNDAY=$(date -u -d "$WEEK_MONDAY + 6 days" +%F)
CUTOFF=$(date -u -d "$TODAY - $((BACKUP_RETENTION_DAYS - 1)) days" +%F)

# A wildly wrong clock must never be able to delete the archive.
EARLIEST_PLAUSIBLE_DATE=2026-01-01
# A prune larger than this share of the dailies is a bug, not a policy.
MAX_PRUNE_SHARE_NUM=6
MAX_PRUNE_SHARE_DEN=10
MAX_PRUNE_SHARE_EXEMPT_COUNT=10

DAILY_KEY="${PREFIX}daily/${TODAY}.tar.gz"
WEEKLY_KEY="${PREFIX}weekly/${TODAY}.tar.gz"

# --- preflight -------------------------------------------------------------

log "target   $BUCKET/${PREFIX}"
log "source   $VOLUME_DATA"
log "endpoint $BACKUP_S3_ENDPOINT (region $BACKUP_S3_REGION)"
log "date     $TODAY  (ISO week $WEEK_MONDAY..$WEEK_SUNDAY, daily cutoff $CUTOFF)"

[ -d "$VOLUME_DATA" ] || fail "volume data dir not found: $VOLUME_DATA"
[ -f "$VOLUME_DATA/data/ghost.db" ] || fail "ghost.db not found under $VOLUME_DATA/data"

rclone lsd "$BUCKET" >/dev/null 2>&1 \
  || fail "cannot reach $BUCKET -- check bucket name, credentials and endpoint"
log "bucket reachable"

if [ "$MODE" = check ]; then
  log "--check passed: config valid, bucket reachable, database present"
  exit 0
fi

# --- lock ------------------------------------------------------------------
# Per site: a slow first image sync for one blog must not block the other.

exec 9>"/var/lock/ghost-backup-$SITE.lock"
flock -n 9 || fail "another backup run for $SITE holds the lock; exiting"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- snapshot the database -------------------------------------------------
# sqlite3 .backup takes a consistent snapshot of a live database, so Ghost
# never goes down for a backup. A plain cp of a database being written to can
# produce a torn file, and if Ghost is ever switched to WAL mode a cp would
# also silently miss everything still sitting in the -wal sidecar.

SNAP="$WORK/ghost.db"
log "snapshotting database"
sqlite3 "$VOLUME_DATA/data/ghost.db" ".backup '$SNAP'"

# .backup inherits the source journal mode and can arrive with -wal/-shm
# sidecars. Collapse to one self-contained file: a backup that is three files
# can be copied incompletely, which is the exact failure this guards against.
sqlite3 "$SNAP" "PRAGMA journal_mode=DELETE;" >/dev/null
rm -f "$SNAP-wal" "$SNAP-shm"

log "verifying snapshot integrity"
result=$(sqlite3 "$SNAP" "PRAGMA integrity_check")
[ "$result" = "ok" ] || fail "integrity check FAILED on the snapshot: $result"
[ -e "$SNAP-wal" ] && fail "snapshot still has WAL sidecars; not a single file"

# --- build the tarball -----------------------------------------------------
# Everything needed to rebuild the blog except the images, which are mirrored
# separately below.

STAGE="$WORK/stage"
mkdir -p "$STAGE/data"
cp "$SNAP" "$STAGE/data/ghost.db"

for dir in settings themes; do
  [ -d "$VOLUME_DATA/$dir" ] && cp -a "$VOLUME_DATA/$dir" "$STAGE/$dir"
done
# routes.yaml and redirects live here and are trivial to forget.
for f in "$VOLUME_DATA"/data/*.json; do
  [ -e "$f" ] && cp -a "$f" "$STAGE/data/"
done

TARBALL="$WORK/${TODAY}.tar.gz"
tar czf "$TARBALL" -C "$STAGE" .
SIZE=$(du -h "$TARBALL" | cut -f1)
log "built snapshot tarball ($SIZE)"

# --- upload the daily ------------------------------------------------------

if [ "$MODE" = dryrun ]; then
  log "DRY RUN: would upload $TARBALL -> $BUCKET/$DAILY_KEY"
else
  log "uploading $DAILY_KEY"
  rclone copyto "$TARBALL" "$BUCKET/$DAILY_KEY" --s3-no-check-bucket
  log "uploaded $DAILY_KEY ($SIZE)"
fi

# --- promote to weekly if this ISO week has none ---------------------------
#
# "First success of the week", not a fixed anchor weekday. With an anchor day,
# one failure that night -- server down, credentials rotated, disk full --
# means the week gets no weekly object at all, and its daily is deleted
# RETENTION_DAYS later. Long-term retention would be lost silently and
# discovered months afterwards.
#
# The BUCKET is the source of truth, not any local state file, so this stays
# correct across a server rebuild.

existing_weekly=$(rclone lsf "$BUCKET/${PREFIX}weekly/" 2>/dev/null \
  | sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.tar\.gz$/\1/p' || true)

have_this_week=no
for d in $existing_weekly; do
  if [[ ! "$d" < "$WEEK_MONDAY" ]] && [[ ! "$d" > "$WEEK_SUNDAY" ]]; then
    have_this_week=yes
    log "ISO week already covered by weekly/$d.tar.gz"
    break
  fi
done

if [ "$have_this_week" = no ]; then
  if [ "$MODE" = dryrun ]; then
    log "DRY RUN: would promote to $WEEKLY_KEY"
  else
    # Server-side copy: no second gzip pass, no second upload.
    log "no weekly for this ISO week yet -- promoting to $WEEKLY_KEY"
    rclone copyto "$BUCKET/$DAILY_KEY" "$BUCKET/$WEEKLY_KEY" --s3-no-check-bucket
    log "promoted $WEEKLY_KEY (kept forever)"
  fi
fi

# --- mirror the images -----------------------------------------------------
#
# `copy`, never `sync`: sync would mirror local deletions up to the bucket, and
# an image that vanishes locally is far more likely to be an accident than an
# intended deletion. The whole point of this half is that every image ever
# published stays recoverable, so this direction is upload-only.
#
# Deliberately NOT --immutable. That flag ABORTS the entire run if any file's
# size or modtime differs from the copy in the bucket, which would turn one odd
# file into a nightly backup failure. Plain copy skips files that already match
# and re-uploads only genuinely differing ones, so it self-heals a truncated
# earlier upload instead of failing forever.

if [ ! -d "$VOLUME_DATA/images" ]; then
  log "no images/ directory; skipping image mirror"
elif [ "$MODE" = dryrun ]; then
  log "DRY RUN: would sync images/"
  rclone copy "$VOLUME_DATA/images" "$BUCKET/${PREFIX}images" --dry-run 2>&1 | tail -5 || true
else
  log "mirroring images (upload-only, never deletes)"
  rclone copy "$VOLUME_DATA/images" "$BUCKET/${PREFIX}images" \
    --transfers 4 \
    --s3-no-check-bucket \
    --stats-one-line --stats 0 || fail "image mirror failed"
  log "image mirror up to date"
fi

# --- prune old dailies -----------------------------------------------------
#
# Runs LAST and must never fail the backup: a stored backup is worth more than
# a tidy bucket. weekly/ and images/ are never touched.

prune() {
  if [[ "$TODAY" < "$EARLIEST_PLAUSIBLE_DATE" ]]; then
    echo "refusing to prune: today is $TODAY, before $EARLIEST_PLAUSIBLE_DATE, so the clock is wrong" >&2
    return 0
  fi

  local keys matched=0 to_delete=()
  keys=$(rclone lsf "$BUCKET/${PREFIX}daily/" 2>/dev/null || true)

  local name date
  for name in $keys; do
    date=$(sed -n 's/^\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\)\.tar\.gz$/\1/p' <<<"$name")
    # Anything we cannot parse is left alone rather than guessed at.
    [ -n "$date" ] || { log "prune: skipping unparseable key daily/$name"; continue; }
    matched=$((matched + 1))
    [[ "$date" < "$CUTOFF" ]] && to_delete+=("$name")
  done

  local n=${#to_delete[@]}
  [ "$n" -eq 0 ] && { log "prune: nothing older than $CUTOFF"; return 0; }

  if [ "$n" -gt "$MAX_PRUNE_SHARE_EXEMPT_COUNT" ] && [ "$matched" -gt 0 ] \
     && [ $((n * MAX_PRUNE_SHARE_DEN)) -gt $((matched * MAX_PRUNE_SHARE_NUM)) ]; then
    echo "refusing to prune: $n of $matched daily objects would be deleted (cutoff $CUTOFF), which looks like a clock jump rather than normal retention" >&2
    return 0
  fi

  if [ "$MODE" = dryrun ]; then
    log "DRY RUN: would prune $n daily object(s) older than $CUTOFF"
    return 0
  fi

  local f
  for f in "${to_delete[@]}"; do
    rclone deletefile "$BUCKET/${PREFIX}daily/$f" && log "pruned daily/$f"
  done
  log "prune: removed $n daily object(s) older than $CUTOFF"
}

prune || log "prune step failed, but the backup itself succeeded"

log "done"
