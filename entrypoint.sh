#!/usr/bin/env bash
# Start password-gated ttyd behind a tiny nginx that exposes /health for Railway.
set -euo pipefail

PORT="${PORT:-8080}"
TTYD_USER="${TTYD_USER:-ubuntu}"
PASSWORD="${TERMINAL_PASSWORD:-}"
TTYD_INTERNAL_PORT="${TTYD_INTERNAL_PORT:-7681}"

if [[ -z "${PASSWORD}" ]]; then
  echo "TERMINAL_PASSWORD is required. Deploy from the template so Railway generates one with \${{secret()}}." >&2
  exit 1
fi

# Refuse the rotting-marketplace default.
if [[ "${PASSWORD}" == "password" || "${PASSWORD}" == "Password" ]]; then
  echo "TERMINAL_PASSWORD must not be the default value 'password'." >&2
  exit 1
fi

mkdir -p /data /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi
chmod 0755 /data
cd /data
export HOME=/data

if [[ ! -e /data/.profile ]]; then
  cat > /data/.profile <<'EOF'
export HOME=/data
export PATH="$HOME/.local/bin:$PATH"
cd /data 2>/dev/null || true
echo "Persistent workspace: /data (survives redeploys). Packages you apt-get install last until the next image rebuild."
EOF
fi

NGINX_CONF="/tmp/nginx.conf"
cat > "${NGINX_CONF}" <<EOF
daemon off;
worker_processes 1;
error_log /dev/stderr warn;
pid /tmp/nginx.pid;
events { worker_connections 64; }
http {
  access_log off;
  server_tokens off;
  client_body_temp_path /tmp/nginx/body;
  proxy_temp_path /tmp/nginx/proxy;
  fastcgi_temp_path /tmp/nginx/fastcgi;
  uwsgi_temp_path /tmp/nginx/uwsgi;
  scgi_temp_path /tmp/nginx/scgi;
  map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
  }
  server {
    listen ${PORT} default_server;
    listen [::]:${PORT} default_server;
    server_name _;
    location = /health {
      add_header Content-Type text/plain;
      add_header Cache-Control "no-store";
      return 200 "ok\\n";
    }
    location / {
      proxy_pass http://127.0.0.1:${TTYD_INTERNAL_PORT};
      proxy_http_version 1.1;
      proxy_set_header Host \$host;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto \$scheme;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
    }
  }
}
EOF

echo "Starting ttyd ${TTYD_USER}@127.0.0.1:${TTYD_INTERNAL_PORT} and nginx on :${PORT}"

ttyd \
  --interface 127.0.0.1 \
  --port "${TTYD_INTERNAL_PORT}" \
  --credential "${TTYD_USER}:${PASSWORD}" \
  --writable \
  --cwd /data \
  --ping-interval 15 \
  --max-clients 8 \
  --terminal-type xterm-256color \
  /bin/bash -l &
ttyd_pid=$!

nginx -c "${NGINX_CONF}" &
nginx_pid=$!

term() {
  kill -TERM "${ttyd_pid}" "${nginx_pid}" 2>/dev/null || true
}
trap term SIGTERM SIGINT

# Exit if either child dies so Railway restarts the whole service.
wait -n "${ttyd_pid}" "${nginx_pid}"
status=$?
term
wait "${ttyd_pid}" "${nginx_pid}" 2>/dev/null || true
exit "${status}"
