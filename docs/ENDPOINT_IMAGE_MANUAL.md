# Build And Push TrustTunnel Endpoint Image (Manual)

Use this flow when endpoint image updates are needed.

## 1) Choose TrustTunnel source

- Use your fork or upstream repository and checkout required ref/tag.

## 2) Build image locally

```bash
docker build -t ghcr.io/<owner>/tt-endpoint:vX.Y.Z ./server
```

If your Dockerfile/context is in another local checkout, adjust path accordingly.

## 3) Login to GHCR

```bash
echo "$GHCR_TOKEN" | docker login ghcr.io -u <github-username> --password-stdin
```

Token should have `write:packages` scope.

## 4) Push image

```bash
docker push ghcr.io/<owner>/tt-endpoint:vX.Y.Z
```

## 5) Capture digest

```bash
docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/<owner>/tt-endpoint:vX.Y.Z
```

Use digest reference in release manifest and installer config for stable deployments.
