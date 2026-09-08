#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
TTYD_USER="${TTYD_USER:-ubuntu}"
PASSWORD="${TERMINAL_PASSWORD:-}"
TTYD_INTERNAL_PORT="${TTYD_INTERNAL_PORT:-7681}"

if [[ -z "${PASSWORD}" ]]; then
  echo "TERMINAL_PASSWORD is required. Deploy from the template so Railway generates one with \${{secret()}}." >&2
  exit 1
fi

if [[ "${PASSWORD,,}" == "password" ]]; then
  echo "TERMINAL_PASSWORD must not be the default value 'password'." >&2
  exit 1
fi

if [[ "${TTYD_USER}" == *:* || "${TTYD_USER}" =~ [[:cntrl:]] ]]; then
  echo "TTYD_USER must not contain colons or control characters." >&2
  exit 1
fi

for port in "${PORT}" "${TTYD_INTERNAL_PORT}"; do
  if [[ ! "${port}" =~ ^[0-9]{1,5}$ ]] || (( 10#${port} < 1 || 10#${port} > 65535 )); then
    echo "Ports must be integers between 1 and 65535." >&2
    exit 1
  fi
done
PORT=$((10#${PORT}))
TTYD_INTERNAL_PORT=$((10#${TTYD_INTERNAL_PORT}))
if [[ "${PORT}" == "${TTYD_INTERNAL_PORT}" ]]; then
  echo "PORT and TTYD_INTERNAL_PORT must differ." >&2
  exit 1
fi

mkdir -p /data /tmp/nginx/body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi
# Migrate files created by older root-shell images without following symlinks.
find /data -xdev -uid 0 -exec chown -h ubuntu:ubuntu {} +
chown ubuntu:ubuntu /data
chmod 0750 /data
for file in .profile .bashrc .bash_logout; do
  if [[ ! -e "/data/${file}" && ! -L "/data/${file}" ]]; then
    install -o ubuntu -g ubuntu -m 0644 "/etc/skel/${file}" "/data/${file}"
  fi
done
cd /data
export HOME=/data

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
      proxy_pass http://127.0.0.1:${TTYD_INTERNAL_PORT}/;
      proxy_set_header Authorization "";
      proxy_set_header Upgrade "";
      proxy_set_header Connection close;
      proxy_connect_timeout 3s;
      proxy_read_timeout 3s;
      proxy_send_timeout 3s;
      proxy_intercept_errors on;
      proxy_hide_header WWW-Authenticate;
      error_page 401 =200 @healthy;
    }
    # Only a live ttyd authentication challenge reaches this internal location.
    location @healthy {
      default_type text/plain;
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

pids=()
cleanup() {
  trap - EXIT TERM INT
  if (( ${#pids[@]} )); then
    kill -TERM "${pids[@]}" 2>/dev/null || true
    kill -CONT "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

echo "Starting password-gated ttyd as ubuntu and nginx on :${PORT}"

runuser -u ubuntu -- env -u TERMINAL_PASSWORD -u PASSWORD HOME=/data USER=ubuntu LOGNAME=ubuntu \
  ttyd \
  --debug 3 \
  --interface 127.0.0.1 \
  --port "${TTYD_INTERNAL_PORT}" \
  --credential "${TTYD_USER}:${PASSWORD}" \
  --writable \
  --cwd /data \
  --ping-interval 15 \
  --max-clients 8 \
  --terminal-type xterm-256color \
  /bin/bash -l &
pids+=("$!")

nginx -c "${NGINX_CONF}" &
pids+=("$!")

# A clean child exit is also unexpected; restart the entire service.
status=0
wait -n "${pids[@]}" || status=$?
if (( status == 0 )); then status=1; fi
exit "${status}"
