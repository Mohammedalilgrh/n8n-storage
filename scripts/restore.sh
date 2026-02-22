#!/bin/sh
set -eu
umask 077

: "${TG_BOT_TOKEN:?}"
: "${TG_CHAT_ID:?}"

N8N_DIR="${N8N_DIR:-/home/node/.n8n}"
WORK="${WORK:-/backup-data}"
HIST="$WORK/history"
TMP="$WORK/_restore_tmp"
TG="https://api.telegram.org/bot${TG_BOT_TOKEN}"

mkdir -p "$N8N_DIR" "$HIST" "$TMP"
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

[ -s "$N8N_DIR/database.sqlite" ] && exit 0

dl_file() {
  fid="$1"; out="$2"
  path=$(curl -sS "${TG}/getFile?file_id=${fid}" | jq -r '.result.file_path // empty')
  [ -n "$path" ] || return 1
  curl -sS -o "$out" "https://api.telegram.org/file/bot${TG_BOT_TOKEN}/${path}"
  [ -s "$out" ]
}

chat=$(curl -sS "${TG}/getChat?chat_id=${TG_CHAT_ID}")
fid=$(echo "$chat" | jq -r '.result.pinned_message.document.file_id // empty')
[ -n "$fid" ] || exit 1

dl_file "$fid" "$TMP/manifest.json"
cp "$TMP/manifest.json" "$HIST/last_restore_manifest.json" || true

jq -r '.files[] | "\(.file_id)|\(.name)"' "$TMP/manifest.json" | while IFS='|' read -r pfid pname; do
  dl_file "$pfid" "$TMP/$pname"
done

if ls "$TMP"/db.sql.gz.part_* >/dev/null 2>&1; then
  cat "$TMP"/db.sql.gz.part_* | gzip -dc | sqlite3 "$N8N_DIR/database.sqlite"
else
  gzip -dc "$TMP/db.sql.gz" | sqlite3 "$N8N_DIR/database.sqlite"
fi

[ -s "$N8N_DIR/database.sqlite" ]
