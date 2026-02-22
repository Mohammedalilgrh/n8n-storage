#!/bin/sh
set -eu
umask 077

: "${TG_BOT_TOKEN:?}"
: "${TG_CHAT_ID:?}"

N8N_DIR="${N8N_DIR:-/home/node/.n8n}"
WORK="${WORK:-/backup-data}"
HIST="$WORK/history"
TMP="$WORK/_backup_tmp"
STATE="$WORK/.backup_state"
LOCK="$WORK/.backup_lock"

MIN_INT="${MIN_BACKUP_INTERVAL_SEC:-300}"
FORCE_INT="${FORCE_BACKUP_EVERY_SEC:-1800}"
GZIP_LVL="${GZIP_LEVEL:-1}"
CHUNK="${CHUNK_SIZE:-19M}"
KEEP="${LOCAL_HISTORY_KEEP:-5}"

TG="https://api.telegram.org/bot${TG_BOT_TOKEN}"

mkdir -p "$WORK" "$HIST"
if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rmdir "$LOCK" 2>/dev/null || true; rm -rf "$TMP" 2>/dev/null || true' EXIT

_db_sig() {
  [ -f "$N8N_DIR/database.sqlite" ] || { echo "missing"; return; }
  stat -c '%Y:%s' "$N8N_DIR/database.sqlite" 2>/dev/null || echo "0:0"
}

_now=$(date +%s)
_last_run=0
_last_force=0
_last_sig=""
if [ -f "$STATE" ]; then
  _last_run=$(grep '^LAST_RUN=' "$STATE" | cut -d= -f2 || echo 0)
  _last_force=$(grep '^LAST_FORCE=' "$STATE" | cut -d= -f2 || echo 0)
  _last_sig=$(grep '^SIG=' "$STATE" | cut -d= -f2 || true)
fi

_sig=$(_db_sig)
[ "$_sig" = "missing" ] && exit 0

if [ $((_now - _last_force)) -lt "$FORCE_INT" ] && [ "$_sig" = "$_last_sig" ]; then
  exit 0
fi
if [ $((_now - _last_run)) -lt "$MIN_INT" ]; then
  exit 0
fi

ID=$(date -u +"%Y-%m-%d_%H-%M-%S")
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$TMP/parts"

sqlite3 "$N8N_DIR/database.sqlite" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
sqlite3 "$N8N_DIR/database.sqlite" ".dump" | gzip -n -"$GZIP_LVL" -c > "$TMP/db.sql.gz"

split -b "$CHUNK" -d -a 3 "$TMP/db.sql.gz" "$TMP/parts/db.sql.gz.part_"

manifest_items=""
count=0
for f in "$TMP/parts"/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  resp=$(curl -sS -X POST "${TG}/sendDocument" \
    -F "chat_id=${TG_CHAT_ID}" \
    -F "document=@${f}" \
    -F "caption=#n8n_backup ${ID} ${name}" || true)
  fid=$(echo "$resp" | jq -r '.result.document.file_id // empty')
  mid=$(echo "$resp" | jq -r '.result.message_id // empty')
  [ -n "$fid" ] || exit 1
  manifest_items="${manifest_items}{\"msg_id\":${mid},\"file_id\":\"${fid}\",\"name\":\"${name}\"},"
  count=$((count + 1))
  sleep 1
done
manifest_items=$(echo "$manifest_items" | sed 's/,$//')

cat > "$TMP/manifest.json" <<JSON
{
  "id": "$ID",
  "timestamp": "$TS",
  "type": "n8n-telegram-backup",
  "version": "5.0",
  "file_count": $count,
  "files": [${manifest_items}]
}
JSON

cp "$TMP/manifest.json" "$HIST/${ID}.json"

manifest_resp=$(curl -sS -X POST "${TG}/sendDocument" \
  -F "chat_id=${TG_CHAT_ID}" \
  -F "document=@$TMP/manifest.json;filename=manifest_${ID}.json" \
  -F "caption=#n8n_manifest #n8n_backup ${ID}")
manifest_mid=$(echo "$manifest_resp" | jq -r '.result.message_id // empty')
if [ -n "$manifest_mid" ]; then
  curl -sS -X POST "${TG}/pinChatMessage" \
    -d "chat_id=${TG_CHAT_ID}" \
    -d "message_id=${manifest_mid}" \
    -d "disable_notification=true" >/dev/null 2>&1 || true
fi

cat > "$STATE" <<EOF2
LAST_RUN=$_now
LAST_FORCE=$_now
SIG=$_sig
ID=$ID
TS=$TS
EOF2

for old in $(ls -t "$HIST"/*.json 2>/dev/null | tail -n +$((KEEP + 1))); do
  rm -f "$old"
done

echo "backup ok: $ID"
