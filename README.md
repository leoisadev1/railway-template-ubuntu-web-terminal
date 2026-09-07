# Ubuntu 24.04 Web Terminal

A persistence-first Ubuntu 24.04 LTS box in the browser. ttyd is pinned to the current upstream release, a password is generated on deploy, `/data` is a real volume, and Railway gets an HTTP healthcheck. This is the maintained replacement for rotting Ubuntu-in-browser marketplace clones (Ubuntu 22.04 + ttyd 1.7.3, no volume, default `password`).

No SSH daemon, no TCP/22, no `PermitRootLogin`, no nmap.

## One-click deploy

1. Open the template on Railway and click **Deploy**.
2. Railway generates `TERMINAL_PASSWORD` via `${{secret()}}`. Copy it from the service **Variables** tab.
3. Open the public HTTPS domain. The browser asks for HTTP basic auth.
4. Username: `ubuntu` (override with `TTYD_USER` if you change it). Password: the generated `TERMINAL_PASSWORD`.
5. Your shell starts in `/data`, which is the mounted volume.

## Variables

| Name | Required | Default | Notes |
| --- | --- | --- | --- |
| `TERMINAL_PASSWORD` | **yes** | `${{secret()}}` | Generated secret. There is no default `password`. The container refuses to boot if this is empty or `password`. |
| `TTYD_USER` | no | `ubuntu` | HTTP basic-auth username. |
| `PORT` | set by Railway | `8080` | Public HTTP port. Do not change. |

## Volume

| Mount | Purpose |
| --- | --- |
| `/data` | Persistent workspace and `HOME`. Files here survive redeploys. |

`apt-get` packages live in the container filesystem: they last until the next image rebuild, not across template upgrades. Keep work product in `/data`.

## Ports

| Port | Public | Service |
| --- | --- | --- |
| `$PORT` (HTTP/HTTPS) | yes | ttyd web terminal + `/health` |
| 22 / TCP | **no** | Not exposed. sshd is not installed. |

## Login

The public URL is password-gated with HTTP basic auth (ttyd `-c`).

```bash
# Healthcheck (no auth)
curl -fsS https://<your-domain>/health

# Login page / auth challenge
curl -I https://<your-domain>/
```

A `401` with `WWW-Authenticate` on `/` is expected until you send `TTYD_USER` / `TERMINAL_PASSWORD`. After login you get an Ubuntu 24.04 bash shell with git, python3, pip, venv, curl, and ca-certificates preinstalled.

## Healthcheck

Railway probes `GET /health`, which returns `200 ok` without credentials so the deployment can pass health while the terminal stays locked.

## Why this listing

| | Typical rotting clone | This template |
| --- | --- | --- |
| Base image | Ubuntu 22.04, often unpinned | Ubuntu 24.04 LTS pinned by digest |
| ttyd | 1.7.3 | 1.7.7, checksum-verified |
| Password | default `password` | required, generated `${{secret()}}` |
| Disk | ephemeral | volume at `/data` |
| Health | missing | HTTP `/health` |
| Process 1 | ad-hoc | tini |
| SSH | sometimes sshd + TCP/22 | none |

PID 1 is tini so ttyd and nginx are reaped on exit. nginx only fronts the local ttyd port so `/health` can stay public while the shell stays authenticated. It is not an open internet proxy.
