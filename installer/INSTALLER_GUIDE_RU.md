# Руководство по установщику TrustTunnel на VPS

Этот каталог содержит bash-установщик для TrustTunnel и Telegram admin bot.

Базовый сценарий:

- pull готовых образов из публичного registry
- базовая настройка VPS (UFW, fail2ban, Docker)
- деплой TrustTunnel endpoint
- деплой Telegram-бота для управления
- запись state и итогового report

Режим первого запуска по умолчанию — интерактивный мастер `setup_wizard`
(`TT_SETUP_MODE=wizard`). Это рекомендованный вариант для свежего сервера.

## Что подготовить заранее

- SSH-доступ к VPS с `sudo`
- Домен (`TT_ENDPOINT_FQDN`), указывающий на публичный IP VPS
- TLS-стратегию:
  - `letsencrypt-http01` — выпуск LE через мастер (нужен `80/tcp`)
  - `existing-cert` — использовать существующий cert/key
  - `self-signed` — только тестовый сценарий
  - `letsencrypt-dns01` — ручной сценарий в текущей версии
- Образ endpoint (`TT_IMAGE`)
- Образ admin bot (`BOT_IMAGE`)
- Токен бота и разрешенные Telegram user IDs
- Для non-interactive режима — bootstrap credentials в `secrets.env`

## Быстрый старт

1. Заполните конфиги:

```bash
chmod 600 secrets.env
```

Минимально обязательные поля:

- `installer.env`
  - `TT_ENDPOINT_FQDN` (REQUIRED)
  - `TT_IMAGE` по умолчанию: `ghcr.io/dzas/tt-endpoint:1.0.33`
  - `BOT_IMAGE` по умолчанию: `ghcr.io/dzas/tt_admin_bot:v1.0.1`
  - `LE_EMAIL` и `LE_DOMAIN` опциональны при `TT_SETUP_MODE=wizard`
  - `LE_EMAIL` и `LE_DOMAIN` обязательны только при `TT_SETUP_MODE=non-interactive` и `TLS_MODE=letsencrypt-http01`

- `secrets.env`
  - `TELEGRAM_BOT_TOKEN` (REQUIRED при `BOT_ENABLE=true`)
  - `TELEGRAM_ALLOWED_USER_IDS` (REQUIRED при `BOT_ENABLE=true`)
  - `TT_BOOTSTRAP_USERNAME` и `TT_BOOTSTRAP_PASSWORD` обязательны только для `TT_SETUP_MODE=non-interactive`

2. Выполните preflight:

```bash
./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive
```

3. Запустите установку:

```bash
./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env
```

4. Если прервалось:

```bash
./tt-installer.sh resume --state /opt/tt-installer/state.json
```

5. Проверка:

```bash
./tt-installer.sh verify --config ./installer.env --secrets ./secrets.env
```

## Команды

- `plan` — проверки и валидация входных данных
- `apply` — полный сценарий установки
- `resume` — продолжить после ошибки/обрыва
- `verify` — только проверки состояния
- `rollback` — подсказки по ручному откату

## Файлы состояния

- state: `/opt/tt-installer/state.json`
- report: `/opt/tt-installer/report.md`

## Важные замечания

- В wizard-режиме обязательно завершайте блок сертификатов до конца, чтобы создался `hosts.toml`.
- `letsencrypt-dns01` пока не автоматизирован. Для стабильного процесса используйте `existing-cert`.
- SSH hardening в текущей версии консервативный (без автоправок `sshd_config`).
- Rollback ручной, через backup-артефакты.
