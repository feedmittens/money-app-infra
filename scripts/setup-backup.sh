#!/usr/bin/env bash
# Sets up automated daily pg_dump backups on the Tally LXC container.
# Run once: bash scripts/setup-backup.sh
# Backups land in /var/backups/tally/ and are kept for 30 days.
set -euo pipefail

CONTAINER="${CONTAINER_ID:-200}"

echo "=== Setting up Tally backup on container $CONTAINER ==="

pct exec "$CONTAINER" -- bash -c 'mkdir -p /var/backups/tally'

# Backup script
pct exec "$CONTAINER" -- bash -c 'cat > /usr/local/bin/tally-backup.sh' << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR=/var/backups/tally
STAMP=$(date +%Y%m%d-%H%M%S)
FILE="$BACKUP_DIR/tally-$STAMP.sql.gz"

pg_dump -U tally tally | gzip > "$FILE"
echo "$(date -Iseconds) backup written: $FILE ($(du -sh "$FILE" | cut -f1))"

# Prune backups older than 30 days
find "$BACKUP_DIR" -name 'tally-*.sql.gz' -mtime +30 -delete
SCRIPT

pct exec "$CONTAINER" -- chmod +x /usr/local/bin/tally-backup.sh

# systemd service unit
pct exec "$CONTAINER" -- bash -c 'cat > /etc/systemd/system/tally-backup.service' << 'UNIT'
[Unit]
Description=Tally PostgreSQL backup
After=postgresql.service

[Service]
Type=oneshot
User=postgres
ExecStart=/usr/local/bin/tally-backup.sh
StandardOutput=journal
StandardError=journal
UNIT

# systemd timer — runs daily at 3am
pct exec "$CONTAINER" -- bash -c 'cat > /etc/systemd/system/tally-backup.timer' << 'TIMER'
[Unit]
Description=Daily Tally PostgreSQL backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

pct exec "$CONTAINER" -- systemctl daemon-reload
pct exec "$CONTAINER" -- systemctl enable --now tally-backup.timer

echo ""
pct exec "$CONTAINER" -- systemctl status tally-backup.timer --no-pager
echo ""
echo "=== Backup timer installed. Test with: ==="
echo "    ssh root@\$PROXMOX_HOST \"pct exec $CONTAINER -- systemctl start tally-backup.service\""
echo "    ssh root@\$PROXMOX_HOST \"pct exec $CONTAINER -- ls -lh /var/backups/tally/\""
