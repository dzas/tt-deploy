# TrustTunnel Deploy Monorepo

Language: [EN](README.md) | [RU](README_RU.md)

Быстрые ссылки:
- Деплой из релиза (EN): `docs/DEPLOY_FROM_RELEASE.md`
- Деплой из релиза (RU): `docs/DEPLOY_FROM_RELEASE_RU.md`
- Руководство по установщику (EN): `installer/INSTALLER_GUIDE.md`
- Руководство по установщику (RU): `installer/INSTALLER_GUIDE_RU.md`
- Сборка образа endpoint (EN): `docs/ENDPOINT_IMAGE_MANUAL.md`
- Сборка образа endpoint (RU): `docs/ENDPOINT_IMAGE_MANUAL_RU.md`
- Чеклист релиза (EN): `docs/RELEASE_CHECKLIST.md`
- Чеклист релиза (RU): `docs/RELEASE_CHECKLIST_RU.md`

Этот репозиторий содержит инструменты для деплоя и управления self-hosted TrustTunnel.

## Состав

- `installer/` — bash-установщик с режимами `plan/apply/resume/verify`.
- `admin_bot/` — исходники Telegram-бота для администрирования.
- `release/` — шаблоны манифестов релиза установщика.
- `docs/` — инструкции по релизу и деплою на VPS.

## Модель поставки

- Образ TrustTunnel endpoint: собирается локально по мере необходимости и публикуется в GHCR.
- Образ admin bot: можно публиковать через GitHub Actions или вручную.
- Установщик: публикуется как versioned tarball в GitHub Releases.

## Примечания

- `server/` хранится локально как reference и не входит в этот deploy-репозиторий.
- Процедура сборки/публикации endpoint образа: `docs/ENDPOINT_IMAGE_MANUAL_RU.md`.

## Деплой на VPS

Рекомендуемый поток:

1. Скачать assets релиза (`installer-<version>.tar.gz`, `manifest-<version>.json`, `SHA256SUMS`).
2. Проверить checksum.
3. Заполнить `installer/installer.env` и `installer/secrets.env`.
4. Запустить:
   - `./tt-installer.sh plan --config ./installer.env --secrets ./secrets.env --interactive`
   - `./tt-installer.sh apply --config ./installer.env --secrets ./secrets.env`

Подробная инструкция: `docs/DEPLOY_FROM_RELEASE_RU.md`.
