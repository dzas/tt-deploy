# TrustTunnel VPS Installer Guide

This directory contains a bash-based installer scaffold for TrustTunnel and the
admin Telegram bot.

It is designed for a simple self-hosted flow:

- pull prebuilt images from a public registry
- configure VPS baseline (UFW, fail2ban, Docker)
- deploy TrustTunnel endpoint
- deploy Telegram management bot
- write progress state and a human-readable report

On first start (when `vpn.toml` / `hosts.toml` / `credentials.toml` are
missing), the container entrypoint runs `setup_wizard` automatically in
non-interactive mode using env variables prepared by installer.

## What To Prepare Before Running

- SSH access to VPS with `sudo`
- Domain name (`TT_ENDPOINT_FQDN`) that resolves to your VPS public IP
- TLS strategy:
  - `letsencrypt-http01`: open `80/tcp` and `443/tcp` (automated via setup_wizard)
  - `letsencrypt-dns01`: manual certificate issuance flow (installer checks DNS only)
  - `existing-cert`: ready `cert` and `key` file paths
  - `self-signed`: testing only
- TrustTunnel image reference (`TT_IMAGE`)
- Telegram bot image reference (`BOT_IMAGE`)
- Telegram bot token and allowed user IDs
- TrustTunnel config files (`vpn.toml`, `hosts.toml`, `credentials.toml`,
  `rules.toml`) in either:
  - `TT_DATA_DIR`, or
  - `TT_CONFIG_SOURCE_DIR` for initial copy

## Quick Start

1. Copy examples and edit values:

```bash
cp installer.env.example installer.env
cp secrets.env.example secrets.env
chmod 600 secrets.env
```

2. Run plan mode:

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
```

`plan` prints a wizard prerequisites checklist with explicit statuses:

- DNS for `TT_ENDPOINT_FQDN`
- DNS for `LE_DOMAIN` (if TLS mode requires it)
- local port 80 availability for ACME HTTP-01
- bootstrap credentials presence for first-time setup_wizard run

3. Apply changes:

```bash
./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
```

4. Continue after interruption:

```bash
./tt-installer.sh resume --state /opt/tt-installer/state.json
```

5. Verify services:

```bash
./tt-installer.sh verify --config ./installer.env --secrets ./secrets.env
```

## Commands

- `plan`: readiness checks and input validation
- `apply`: full installation flow
- `resume`: continue failed/interrupted run
- `verify`: service checks only
- `rollback`: currently prints rollback hints (manual restore in v1)

## State And Report Files

- state: `/opt/tt-installer/state.json`
- report: `/opt/tt-installer/report.md`

The installer updates state after each step and writes report entries with
status and notes.

## Current v1 Notes

- `letsencrypt-dns01` is manual in v1. setup_wizard non-interactive mode only
  supports ACME HTTP-01. For DNS-01, issue certs manually and then use
  `TLS_MODE=existing-cert`.
- SSH hardening step is conservative in v1 and does not auto-edit
  `sshd_config`.
- Rollback is manual in v1, using snapshot files from backup step.
