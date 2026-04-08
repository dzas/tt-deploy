# TrustTunnel Personal Project Context

## Purpose

This repository is used for learning and personal self-hosted usage of the
open-source TrustTunnel VPN server.

- Upstream project: https://github.com/TrustTunnel/TrustTunnel
- Personal scope: private environment, non-commercial usage

## Repository Scope

- `server/` contains the upstream server source code (git repository mirror).
- Do not modify files in `server/` unless explicitly requested.
- This root `AGENTS.md` is the primary living context for AI assistants.

## Deployment Environment

- Provider/type: VPS (Europe)
- OS: Ubuntu 20.04.6 LTS (`focal`)
- Kernel: `5.4.0-216-generic`
- Docker: `28.1.1`
- Docker Compose: `v2.35.1`

## Service Scope

- Single service role: TrustTunnel only
- FQDN: `tt.example.com`
- Public IPv4: `<public-ipv4>`
- IPv6: not used

## Access And Security Baseline

- SSH port: `22/tcp`
- Root login: denied
- SSH auth mode: key + password
- UFW: enabled (`deny incoming`, `allow outgoing`)
- Fail2ban: enabled, jail list includes `sshd`

## Runtime Management

### Start/Restart

Path: `/usr/local/bin/tt-up`

```bash
#!/usr/bin/env bash
set -euo pipefail
sudo docker rm -f trusttunnel 2>/dev/null || true
sudo docker run -d \
  --name trusttunnel \
  --restart unless-stopped \
  --network host \
  --cap-add=NET_ADMIN \
  --device=/dev/net/tun \
  -v /opt/trusttunnel:/trusttunnel_endpoint \
  trusttunnel-endpoint:fixed \
  /usr/bin/trusttunnel_endpoint /trusttunnel_endpoint/vpn.toml /trusttunnel_endpoint/hosts.toml -l debug
```

### Stop

Path: `/usr/local/bin/tt-down`

```bash
#!/usr/bin/env bash
set -euo pipefail
sudo docker rm -f trusttunnel 2>/dev/null || true
```

### Data/Config Location

- TrustTunnel data directory: `/opt/trusttunnel/`
- Expected config files: `vpn.toml`, `hosts.toml`, `credentials.toml`, `rules.toml`

## TLS

- Certificate type: Let's Encrypt
- Renewal process: manual (exact command flow not documented yet)
- TODO: document exact renewal steps and post-renew reload/restart procedure

## Firewall Notes

- Keep baseline minimum ports documented and audited per environment.
- Typical baseline for this project: `22/tcp`, `80/tcp` (when using ACME HTTP-01), `443/tcp`.

## Backup Policy

- No backups are maintained.
- Recovery model: redeploy from scratch when needed.

## AI Operating Rules

1. Do not execute commands on the server autonomously.
2. Provide step-by-step commands and explain risks before impactful changes.
3. Any changes to SSH/UFW/Fail2ban/Docker require explicit user confirmation.
4. Safety priority: preserve SSH access and current TrustTunnel availability.
5. Do not propose storing secrets in repository files.

## Current Gaps / TODO

- Document Let's Encrypt manual renewal workflow.
- Add a minimal health-check routine (what to run and expected output).
- Audit UFW rules and mark active vs legacy ports.

## Change Log (Project Context)

Use this section for ongoing updates to operational context.

- 2026-04-05: Created initial project context document at repository root.
