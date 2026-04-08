# TrustTunnel AdminBot

Telegram bot for basic TrustTunnel user management on a self-hosted server.

## Features

- `/list` - list users from `credentials.toml`
- `/link <username>` - generate `tt://` link and QR page URL
- `/add <username> <password>` - add user, backup credentials file, restart container
- `/del <username>` - remove user, backup credentials file, restart container
- `/health` - show container status and users count

## Security Model

- Access is restricted by `TELEGRAM_ALLOWED_USER_IDS`.
- Bot token must be provided via environment variable.
- The bot requires Docker socket access to restart TrustTunnel.
- Before editing `credentials.toml`, the bot creates `credentials.toml.bak.<timestamp>`.

## Environment Variables

- `TELEGRAM_BOT_TOKEN` - Telegram bot token (required)
- `TELEGRAM_ALLOWED_USER_IDS` - comma-separated Telegram user IDs (required)
- `TT_CONTAINER_NAME` - TrustTunnel container name (default: `trusttunnel`)
- `TT_ENDPOINT_ADDRESS` - endpoint address for generated links (default: `tt.example.com:443`)
- `TT_CREDENTIALS_PATH` - host path to credentials file (default: `/opt/trusttunnel/credentials.toml`)
- `TT_VPN_CONFIG_PATH_IN_CONTAINER` - path to `vpn.toml` inside TrustTunnel container
- `TT_HOSTS_CONFIG_PATH_IN_CONTAINER` - path to `hosts.toml` inside TrustTunnel container

## Build

```bash
docker build -t trusttunnel-admin-bot:latest ./admin_bot
```

If you build in GitHub Actions and publish to GHCR, use image refs like:

```text
ghcr.io/<owner>/tt_admin_bot:<tag>
```

This repository includes workflow `/.github/workflows/admin-bot-publish.yml`.
It pushes image tags to `ghcr.io/<owner>/tt_admin_bot` on pushes to `main`, tags, and manual runs.

## Run

```bash
docker run -d \
  --name trusttunnel-admin-bot \
  --restart unless-stopped \
  --env-file /path/to/.env \
  -v /opt/trusttunnel:/opt/trusttunnel \
  -v /var/run/docker.sock:/var/run/docker.sock \
  trusttunnel-admin-bot:latest
```

## Local Run (Docker Desktop)

This repo includes a local test setup with a mock `trusttunnel` container.
It is useful to test bot commands without a real VPN endpoint.

1. Copy local env template:

```bash
cp .env.local.example .env.local
```

2. Update `.env.local` with your real values:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USER_IDS`

3. Start local stack:

```bash
docker compose -f docker-compose.local.yml up -d --build
```

4. Check logs:

```bash
docker logs -f trusttunnel-admin-bot
```

5. Stop local stack:

```bash
docker compose -f docker-compose.local.yml down
```

Local test data is stored in `./local/data`.

## Deploy On VPS From Registry

Use `deploy.sh` to pull a prebuilt image and restart the bot container:

```bash
chmod +x ./admin_bot/deploy.sh
./admin_bot/deploy.sh ghcr.io/<owner>/tt_admin_bot:latest
```

Defaults used by script:

- `CONTAINER_NAME=trusttunnel-admin-bot`
- `ENV_FILE=/opt/trusttunnel-admin-bot/.env`
- `TT_DATA_DIR=/opt/trusttunnel`

You can override them:

```bash
CONTAINER_NAME=tt-admin-bot ENV_FILE=/opt/tt-admin/.env TT_DATA_DIR=/opt/trusttunnel \
  ./admin_bot/deploy.sh ghcr.io/<owner>/tt_admin_bot:v1
```

## Multi-Server Deployment

Use one bot instance per server and one unique Telegram token per instance.

- Recommended model: same codebase, separate bot token on each server.
- Do not run multiple instances with the same token in long polling mode.
- Set `TELEGRAM_ALLOWED_USER_IDS` per server to restrict admin access.

## Telegram Registration

Register each server bot in Telegram via `@BotFather`:

1. Send `/newbot`.
2. Set bot name and unique username.
3. Save the issued token into `TELEGRAM_BOT_TOKEN` on that server.
4. Get your Telegram numeric user ID (for example, via `@userinfobot`) and set `TELEGRAM_ALLOWED_USER_IDS`.

## Notes

- Commands are intentionally minimal for private usage.
- Passwords with spaces are not supported by `/add` command syntax.
