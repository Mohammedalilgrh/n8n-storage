diff --git a/scripts/bot.sh b/scripts/bot.sh
new file mode 100755
index 0000000000000000000000000000000000000000..3b31225af1e500e8f5bfe013b0d4a0dffeeb5c0b
--- /dev/null
+++ b/scripts/bot.sh
@@ -0,0 +1,30 @@
+#!/bin/sh
+set -eu
+
+: "${TG_BOT_TOKEN:?}"
+: "${TG_ADMIN_ID:?}"
+
+TG="https://api.telegram.org/bot${TG_BOT_TOKEN}"
+OFFSET=0
+
+send_msg() {
+  txt="$1"
+  curl -sS -X POST "${TG}/sendMessage" -d "chat_id=${TG_ADMIN_ID}" -d "text=${txt}" >/dev/null 2>&1 || true
+}
+
+while true; do
+  updates=$(curl -sS "${TG}/getUpdates?offset=${OFFSET}&timeout=20" || true)
+  echo "$updates" | jq -c '.result[]?' | while read -r u; do
+    uid=$(echo "$u" | jq -r '.update_id')
+    OFFSET=$((uid + 1))
+    from=$(echo "$u" | jq -r '.message.from.id // 0')
+    text=$(echo "$u" | jq -r '.message.text // empty')
+    [ "$from" = "$TG_ADMIN_ID" ] || continue
+    case "$text" in
+      /start|/menu) send_msg "n8n backup bot ready. Commands: /status /backup" ;;
+      /status) [ -s /home/node/.n8n/database.sqlite ] && send_msg "DB: OK" || send_msg "DB: missing" ;;
+      /backup) sh /scripts/backup.sh >/tmp/backup_run.log 2>&1 && send_msg "backup done" || send_msg "backup failed" ;;
+    esac
+  done
+  sleep 2
+done
