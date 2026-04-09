# Deploy From GitHub Release

## Prerequisites

- Ubuntu VPS with SSH access.
- Installed packages: `curl`, `tar`, `jq`, `sha256sum`, `sudo`, `docker`.
- Domain DNS records already configured.

## Download Installer Assets

```bash
VERSION=v0.1.0
OWNER=dzas
REPO=tt-deploy
BASE="https://github.com/${OWNER}/${REPO}/releases/download/${VERSION}"

curl -fL -o installer.tar.gz "${BASE}/installer-${VERSION}.tar.gz"
curl -fL -o manifest.json "${BASE}/manifest-${VERSION}.json"
curl -fL -o SHA256SUMS "${BASE}/SHA256SUMS"
sha256sum -c SHA256SUMS
```

## Unpack And Configure

```bash
mkdir -p /opt/tt-release && tar -xzf installer.tar.gz -C /opt/tt-release
cd /opt/tt-release/installer
chmod 600 secrets.env
```

Edit `installer.env` and `secrets.env` with your values.

Minimum required values:

- `installer.env`
  - `TT_ENDPOINT_FQDN` (REQUIRED)
  - `TT_IMAGE` / `BOT_IMAGE` (defaults are provided in file)
  - `TLS_MODE` (default: `letsencrypt-http01`)
- `secrets.env`
  - `TELEGRAM_BOT_TOKEN` (REQUIRED when `BOT_ENABLE=true`)
  - `TELEGRAM_ALLOWED_USER_IDS` (REQUIRED when `BOT_ENABLE=true`)

## Run Installer

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
```

Default first-run mode is `TT_SETUP_MODE=wizard`, so you will complete
certificate generation in interactive setup wizard.

If interrupted:

```bash
./tt-installer.sh resume --state /opt/tt-installer/state.json
```

## Verify

```bash
./tt-installer.sh verify --config ./installer.env --secrets ./secrets.env
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```
