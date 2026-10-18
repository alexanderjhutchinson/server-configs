#!/usr/bin/env bash
# Weekly backup of alex-cloud state -> restic repository on alex-cloud-gaming
set -euo pipefail

# --- config ---
export RESTIC_REPOSITORY="rest:http://alex-cloud-gaming:8000/alex-cloud"
export RESTIC_PASSWORD_FILE="/root/.restic-password"
STAGING="/srv/backup-staging"

NC_APP="nextcloud-app"
NC_DB="nextcloud-db"
NPM_DIR="/srv/docker-nginx-proxy/nginx-proxy-manager"
GRAFANA_DB="/var/lib/docker/volumes/docker-monitoring_grafana-data/_data/grafana.db"

log() { echo "[$(date '+%F %T')] $*"; }

maintenance() {
  docker exec -u www-data "$NC_APP" php occ maintenance:mode "--$1"
}

# Runs on ANY exit (success or failure): Nextcloud never stays in maintenance mode
cleanup() {
  maintenance off || log "WARNING: could not turn off maintenance mode"
  rm -rf "$STAGING"
}
trap cleanup EXIT

rm -rf "$STAGING"
mkdir -p "$STAGING"

log "Nextcloud maintenance mode on"
maintenance on

log "Dumping Nextcloud database"
# Single quotes: the variables expand INSIDE the container, so no password lives in this script
docker exec "$NC_DB" sh -c 'exec mariadb-dump --single-transaction -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  > "$STAGING/nextcloud.sql"

log "Snapshotting SQLite databases"
sqlite3 "$NPM_DIR/data/database.sqlite" ".backup '$STAGING/npm.sqlite'"
sqlite3 "$GRAFANA_DB" ".backup '$STAGING/grafana.db'"

log "Running restic backup"
restic backup --tag weekly \
  --exclude '/srv/docker-nextcloud/nextcloud/data/appdata_*/preview' \
  "$STAGING" \
  /srv/docker-nextcloud/nextcloud \
  "$NPM_DIR/data" \
  "$NPM_DIR/letsencrypt" \
  /srv/docker-nextcloud/.env \
  /srv/docker-monitoring/.env \
  /srv/server-configs/nextcloud/.env

log "Backup complete"
