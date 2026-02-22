#!/bin/sh
set -eu
umask 077

N8N_DIR="${N8N_DIR:-/home/node/.n8n}"
WORK="${WORK:-/backup-data}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-120}"

mkdir -p "$N8N_DIR" "$WORK" "$WORK/history"
export HOME="/home/node"

: "${TG_BOT_TOKEN:?Set TG_BOT_TOKEN}"
: "${TG_CHAT_ID:?Set TG_CHAT_ID}"
: "${TG_ADMIN_ID:?Set TG_ADMIN_ID}"

for cmd in curl jq sqlite3 gzip split; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing command: $cmd"; exit 1; }
done

if [ ! -s "$N8N_DIR/database.sqlite" ]; then
  sh /scripts/restore.sh || true
fi

(
  sleep 15
  sh /scripts/bot.sh 2>&1 | sed 's/^/[bot] /'
) &

(
  sleep 45
  rm -f "$WORK/.backup_state"
  sh /scripts/backup.sh 2>&1 | sed 's/^/[backup] /' || true
  while true; do
    sleep "$MONITOR_INTERVAL"
    sh /scripts/backup.sh 2>&1 | sed 's/^/[backup] /' || true
  done
) &

exec n8n start
