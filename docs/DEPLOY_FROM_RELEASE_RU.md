# Деплой из GitHub Release

## Требования

- Ubuntu VPS с SSH-доступом
- Установленные пакеты: `curl`, `tar`, `jq`, `sha256sum`, `sudo`, `docker`
- DNS-записи домена уже настроены

## Скачать assets установщика

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

## Распаковать и настроить

```bash
mkdir -p /opt/tt-release && tar -xzf installer.tar.gz -C /opt/tt-release
cd /opt/tt-release/installer
chmod 600 secrets.env
```

Заполните `installer.env` и `secrets.env`.

Минимально обязательные значения:

- `installer.env`
  - `TT_ENDPOINT_FQDN` (REQUIRED)
  - `TT_IMAGE` / `BOT_IMAGE` (дефолты уже заданы)
  - `TLS_MODE` (по умолчанию `letsencrypt-http01`)
- `secrets.env`
  - `TELEGRAM_BOT_TOKEN` (REQUIRED при `BOT_ENABLE=true`)
  - `TELEGRAM_ALLOWED_USER_IDS` (REQUIRED при `BOT_ENABLE=true`)

## Запуск установщика

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
```

По умолчанию первый запуск идет в `TT_SETUP_MODE=wizard`, поэтому выпуск
сертификата выполняется в интерактивном мастере.

Если установка прервалась:

```bash
./tt-installer.sh resume --state /opt/tt-installer/state.json
```

## Проверка

```bash
./tt-installer.sh verify --config ./installer.env --secrets ./secrets.env
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```
