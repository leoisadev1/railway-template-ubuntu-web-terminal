# Deploy and Host Ubuntu 24.04 Web Terminal on Railway

Ubuntu 24.04 LTS in the browser via pinned ttyd. Railway generates a password, mounts `/data` as a real volume, and probes `/health`. This is the persistence-first replacement for rotting Ubuntu-in-browser clones (Ubuntu 22.04 + ttyd 1.7.3, no volume, default `password`).

No SSH daemon, no TCP/22, no `PermitRootLogin`, no nmap.

## About Hosting Ubuntu 24.04 Web Terminal

The image is Ubuntu 24.04 LTS pinned by digest. PID 1 is tini. ttyd 1.7.7 is checksum-verified (not ancient 1.7.3). HTTP basic auth is required: username `ubuntu`, password from generated `TERMINAL_PASSWORD`. nginx only fronts local ttyd so `/health` can return 200 without unlocking the shell. It is not an open internet proxy.

One-click deploy:

1. Click **Deploy** on this template.
2. Copy `TERMINAL_PASSWORD` from the service **Variables** tab (`${{secret()}}`).
3. Open the public HTTPS domain. The browser shows HTTP basic auth.
4. Log in as `ubuntu` with the generated password.
5. Your shell starts in `/data`, which is the mounted volume.

### Variables

| Name | Required | Default | Notes |
| --- | --- | --- | --- |
| `TERMINAL_PASSWORD` | **yes** | `${{secret()}}` | Generated secret. There is no default `password`. The container refuses to boot if this is empty or `password`. |
| `TTYD_USER` | no | `ubuntu` | Optional HTTP basic-auth username override. |
| `PORT` | set by Railway | `8080` | Public HTTP port. Do not change. |

### Volume

| Mount | Purpose |
| --- | --- |
| `/data` | Persistent workspace and `HOME`. Files here survive redeploys. |

`apt-get` packages live in the container filesystem: they last until the next image rebuild, not across template upgrades. Keep work product in `/data`.

### Ports

| Port | Public | Service |
| --- | --- | --- |
| `$PORT` (HTTP/HTTPS) | yes | ttyd web terminal + `/health` |
| 22 / TCP | **no** | Not exposed. sshd is not installed. |

### Login

```bash
# Healthcheck (no auth)
curl -fsS https://<your-domain>/health

# Auth challenge / login prompt
curl -I https://<your-domain>/
```

A `401` with `WWW-Authenticate` on `/` is expected until you send `ubuntu` / `TERMINAL_PASSWORD`. After login you get Ubuntu 24.04 bash with git, python3, pip, venv, curl, and ca-certificates.

Railway probes `GET /health`, which returns `200 ok` without credentials so the deployment can pass health while the terminal stays locked.

### Why this listing is healthier

| | Typical rotting clone | This template |
| --- | --- | --- |
| Base image | Ubuntu 22.04, often unpinned | Ubuntu 24.04 LTS pinned by digest |
| ttyd | 1.7.3 | 1.7.7, checksum-verified |
| Password | default `password` | required, generated `${{secret()}}` |
| Disk | ephemeral | volume at `/data` |
| Health | missing | HTTP `/health` |
| Process 1 | ad-hoc | tini |
| SSH | sometimes sshd + TCP/22 | none |

## Common Use Cases

- A persistent Ubuntu workspace in the browser for diagnostics and small scripts.
- A throwaway-but-sticky Linux box without exposing SSH or TCP/22.
- Replacing Ubuntu-Linux / ttyd 1.7.3 marketplace clones that lose files on redeploy.

## Dependencies for Ubuntu 24.04 Web Terminal Hosting

- Ubuntu 24.04 LTS (pinned digest).
- ttyd 1.7.7 from the upstream GitHub release (checksum-verified).
- tini as PID 1.
- A Railway volume mounted at `/data`.
- A public HTTP domain for ttyd.

### Deployment Dependencies

- Ubuntu Docker image: https://hub.docker.com/_/ubuntu
- ttyd releases: https://github.com/tsl0922/ttyd/releases
- Source: https://github.com/leoisadev1/railway-template-ubuntu-web-terminal

## Why Deploy Ubuntu 24.04 Web Terminal on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Ubuntu 24.04 Web Terminal on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
