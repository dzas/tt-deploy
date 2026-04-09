# TrustTunnel AdminBot

Language: [EN](README.md) | [RU](README_RU.md)

Документация репозитория:
- Monorepo deploy (EN): `../README.md`
- Monorepo deploy (RU): `../README_RU.md`
- Installer guide (EN): `../installer/INSTALLER_GUIDE.md`
- Installer guide (RU): `../installer/INSTALLER_GUIDE_RU.md`

Telegram-бот для базового управления пользователями TrustTunnel на self-hosted сервере.

## Возможности

- `/list` — показать пользователей из `credentials.toml`
- `/link <username>` — сгенерировать `tt://` ссылку и URL страницы с QR
- `/add <username> <password>` — добавить пользователя, сделать backup, перезапустить контейнер
- `/del <username>` — удалить пользователя, сделать backup, перезапустить контейнер
- `/health` — показать статус контейнера и число пользователей

## Безопасность

- Доступ ограничен списком `TELEGRAM_ALLOWED_USER_IDS`.
- Токен бота задается через переменную окружения.
- Для перезапуска TrustTunnel нужен доступ к Docker socket.
- Перед изменением `credentials.toml` создается backup `credentials.toml.bak.<timestamp>`.

## Переменные окружения

- `TELEGRAM_BOT_TOKEN` — токен Telegram-бота (обязательно)
- `TELEGRAM_ALLOWED_USER_IDS` — список Telegram user ID через запятую (обязательно)
- `TT_CONTAINER_NAME` — имя контейнера TrustTunnel (по умолчанию: `trusttunnel`)
- `TT_ENDPOINT_ADDRESS` — endpoint для генерации ссылок (по умолчанию: `tt.example.com:443`)
- `TT_CREDENTIALS_PATH` — путь к `credentials.toml` на хосте (по умолчанию: `/opt/trusttunnel/credentials.toml`)
- `TT_VPN_CONFIG_PATH_IN_CONTAINER` — путь к `vpn.toml` внутри контейнера TrustTunnel
- `TT_HOSTS_CONFIG_PATH_IN_CONTAINER` — путь к `hosts.toml` внутри контейнера TrustTunnel

## Сборка

```bash
docker build -t trusttunnel-admin-bot:latest ./admin_bot
```

Образ в GHCR:

```text
ghcr.io/<owner>/tt_admin_bot:<tag>
```

## Запуск

```bash
docker run -d \
  --name trusttunnel-admin-bot \
  --restart unless-stopped \
  --env-file /path/to/.env \
  -v /opt/trusttunnel:/opt/trusttunnel \
  -v /var/run/docker.sock:/var/run/docker.sock \
  trusttunnel-admin-bot:latest
```

## Локальный запуск (Docker Desktop)

1. Скопировать шаблон локального env:

```bash
cp .env.local.example .env.local
```

2. Заполнить `.env.local`:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USER_IDS`

3. Поднять стек:

```bash
docker compose -f docker-compose.local.yml up -d --build
```

4. Логи:

```bash
docker logs -f trusttunnel-admin-bot
```

5. Остановить стек:

```bash
docker compose -f docker-compose.local.yml down
```

Локальные тестовые данные хранятся в `./local/data`.

## Деплой на VPS из registry

```bash
chmod +x ./admin_bot/deploy.sh
./admin_bot/deploy.sh ghcr.io/<owner>/tt_admin_bot:latest
```

Значения по умолчанию в скрипте:

- `CONTAINER_NAME=trusttunnel-admin-bot`
- `ENV_FILE=/opt/trusttunnel-admin-bot/.env`
- `TT_DATA_DIR=/opt/trusttunnel`

Переопределение:

```bash
CONTAINER_NAME=tt-admin-bot ENV_FILE=/opt/tt-admin/.env TT_DATA_DIR=/opt/trusttunnel \
  ./admin_bot/deploy.sh ghcr.io/<owner>/tt_admin_bot:v1
```

## Деплой на несколько серверов

- Один экземпляр бота на один сервер.
- Для каждого сервера — отдельный Telegram token.
- Не запускать несколько long polling ботов с одним и тем же токеном.

## Регистрация бота в Telegram

Через `@BotFather`:

1. Отправить `/newbot`.
2. Задать имя и username.
3. Сохранить токен в `TELEGRAM_BOT_TOKEN` на сервере.
4. Узнать свой numeric user ID (например через `@userinfobot`) и записать в `TELEGRAM_ALLOWED_USER_IDS`.

## Примечания

- Команды минимальные и рассчитаны на private usage.
- Пароли с пробелами в `/add` не поддерживаются.
