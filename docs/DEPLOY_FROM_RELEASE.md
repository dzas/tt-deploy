# Deploy From GitHub Release

## Prerequisites

- Ubuntu VPS with SSH access.
- Installed packages: `curl`, `tar`, `jq`, `sha256sum`.
- Domain DNS records already configured.

## Download Installer Assets

```bash
VERSION=v0.1.0
OWNER=<owner>
REPO=<repo>
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

## Run Installer

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
```

If interrupted:

```bash
./tt-installer.sh resume --state /opt/tt-installer/state.json
```
