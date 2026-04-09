# Ручная сборка и публикация образа TrustTunnel Endpoint

Используйте этот сценарий, когда нужно обновить endpoint image.

## 1) Выбрать источник TrustTunnel

- Используйте upstream или свой fork и переключитесь на нужный ref/tag.

## 2) Собрать образ локально

```bash
docker build -t ghcr.io/<owner>/tt-endpoint:vX.Y.Z ./server
```

Если Dockerfile/контекст в другом checkout, скорректируйте путь.

## 3) Логин в GHCR

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-username> --password-stdin
```

Токен должен иметь scope `write:packages`.

## 4) Публикация образа

```bash
docker push ghcr.io/<owner>/tt-endpoint:vX.Y.Z
```

## 5) Получить digest

```bash
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/<owner>/tt-endpoint:vX.Y.Z
```

Для стабильных деплоев указывайте digest в манифесте и `installer.env`.
