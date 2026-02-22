FROM docker.n8n.io/n8nio/n8n:2.7.4

USER root

RUN set -eux; \
  if command -v apk >/dev/null 2>&1; then \
    apk add --no-cache curl jq sqlite tar gzip coreutils findutils ca-certificates; \
  elif command -v apt-get >/dev/null 2>&1; then \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl jq sqlite3 tar gzip coreutils findutils ca-certificates; \
    rm -rf /var/lib/apt/lists/*; \
  else \
    echo "No supported package manager found"; \
    exit 1; \
  fi

RUN mkdir -p /scripts /backup-data /home/node/.n8n && \
  chown -R node:node /home/node/.n8n /scripts /backup-data

COPY --chown=node:node scripts/ /scripts/
RUN sed -i 's/\r$//' /scripts/*.sh && chmod 0755 /scripts/*.sh

USER node
WORKDIR /home/node

ENTRYPOINT ["sh", "/scripts/start.sh"]
