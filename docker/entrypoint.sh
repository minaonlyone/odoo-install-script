#!/bin/bash
set -e

CONF=/etc/odoo-server.conf
DB_HOST=$(awk -F' = ' '/^db_host/{print $2}' "$CONF")
DB_PORT=$(awk -F' = ' '/^db_port/{print $2}' "$CONF")

if [ -n "$DB_HOST" ]; then
  echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT} ..."
  for _ in $(seq 1 120); do
    pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" >/dev/null 2>&1 && break
    sleep 1
  done
  pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" >/dev/null 2>&1 || {
    echo "ERROR: PostgreSQL at ${DB_HOST}:${DB_PORT} never answered." >&2; exit 1; }
  echo "PostgreSQL is up."
fi

# The data directory holds the filestore and sessions; keep it on the volume.
mkdir -p /var/lib/odoo
chown -R odoo:odoo /var/lib/odoo /odoo/custom/addons 2>/dev/null || true

# "odoo-bin" in the foreground is what Docker wants, not the init script.
exec sudo -u odoo /odoo/odoo-server/odoo-bin \
  --config="$CONF" \
  --data-dir=/var/lib/odoo \
  "$@"
