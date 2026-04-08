# TrustTunnel VPS Installer Guide

This directory contains a bash-based installer scaffold for TrustTunnel and the
admin Telegram bot.

It is designed for a simple self-hosted flow:

- pull prebuilt images from a public registry
- configure VPS baseline (UFW, fail2ban, Docker)
- deploy TrustTunnel endpoint
- deploy Telegram management bot
- write progress state and a human-readable report

Default first-run mode is interactive `setup_wizard` execution (`TT_SETUP_MODE=wizard`).
This is the recommended baseline for fresh servers.

## What To Prepare Before Running

- SSH access to VPS with `sudo`
- Domain name (`TT_ENDPOINT_FQDN`) that resolves to your VPS public IP
- TLS strategy:
  - `letsencrypt-http01`: wizard-driven Let's Encrypt issuance (port `80/tcp` required)
  - `existing-cert`: use existing cert/key paths
  - `self-signed`: testing only
  - `letsencrypt-dns01`: manual in current installer version
- TrustTunnel image reference (`TT_IMAGE`)
- Telegram bot image reference (`BOT_IMAGE`)
- Telegram bot token and allowed user IDs
- If using non-interactive setup mode, define bootstrap credentials in `secrets.env`

## Quick Start

1. Edit configuration files:

```bash
chmod 600 secrets.env
```

Required fields before first run:

- `installer.env`
  - `TT_ENDPOINT_FQDN` (REQUIRED)
  - `TT_IMAGE` has default value `ghcr.io/dzas/tt-endpoint:1.0.33`
  - `BOT_IMAGE` has default value `ghcr.io/dzas/tt_admin_bot:v1.0.1`
  - `LE_EMAIL` and `LE_DOMAIN` are optional in `TT_SETUP_MODE=wizard`
  - `LE_EMAIL` and `LE_DOMAIN` are REQUIRED only in `TT_SETUP_MODE=non-interactive` with `TLS_MODE=letsencrypt-http01`

- `secrets.env`
  - `TELEGRAM_BOT_TOKEN` (REQUIRED when `BOT_ENABLE=true`)
  - `TELEGRAM_ALLOWED_USER_IDS` (REQUIRED when `BOT_ENABLE=true`)
  - `TT_BOOTSTRAP_USERNAME` and `TT_BOOTSTRAP_PASSWORD` are REQUIRED only in `TT_SETUP_MODE=non-interactive`

2. Run plan mode:

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
```

`plan` prints a prerequisites checklist with explicit statuses:

- DNS for `TT_ENDPOINT_FQDN`
- DNS for `LE_DOMAIN` (mainly relevant in non-interactive LE mode)
- local port 80 availability for ACME HTTP-01
- bootstrap credentials presence for first-time non-interactive mode

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

## Current Notes

- Interactive wizard mode is the default baseline for fresh deployments.
- In wizard mode, complete certificate questions fully so `hosts.toml` is created.
- `letsencrypt-dns01` is manual. For stable automation, issue certs manually and
  then use `TLS_MODE=existing-cert`.
- SSH hardening step is conservative in v1 and does not auto-edit
  `sshd_config`.
- Rollback is manual in v1, using snapshot files from backup step.
