# Чеклист релиза

## 1) Endpoint image (ручная локальная сборка)

- Собрать образ TrustTunnel endpoint локально из нужного ref/tag.
- Запушить образ в GHCR: `ghcr.io/<owner>/tt-endpoint:<version>`.
- Зафиксировать digest для релизных заметок/манифеста.

## 2) Admin bot image

- Убедиться, что изменения `admin_bot/` готовы к выпуску.
- Опубликовать образ в GHCR (через Actions или вручную).
- Проверить тег/версию: `ghcr.io/<owner>/tt_admin_bot:<version>`.

## 3) Installer bundle (GitHub Release)

- Создать git-тег: `vX.Y.Z`.
- Проверить публикацию assets:
  - `installer-vX.Y.Z.tar.gz`
  - `manifest-vX.Y.Z.json`
  - `SHA256SUMS`

## 4) Проверка manifest

- Открыть `manifest-vX.Y.Z.json`.
- Проверить, что ссылки на образы endpoint и bot соответствуют целевым версиям.
- Для production предпочтительны digest-ссылки (`@sha256:...`).

## 5) Smoke test

- На чистом VPS запустить `plan`.
- Запустить `apply` с целевыми image refs.
- Проверить здоровье endpoint и бота.
