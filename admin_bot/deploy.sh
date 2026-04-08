#!/usr/bin/env bash
set -euo pipefail

# Deploys TrustTunnel AdminBot on VPS from a prebuilt container image.
#
# Usage:
#   ./deploy.sh <image_ref>
#
# Example:
#   ./deploy.sh ghcr.io/your-org/trusttunnel-admin-bot:latest
#
# Required runtime env file (example at admin_bot/.env.example):
#   /opt/trusttunnel-admin-bot/.env

IMAGE_REF="${1:-}"
CONTAINER_NAME="${CONTAINER_NAME:-trusttunnel-admin-bot}"
ENV_FILE="${ENV_FILE:-/opt/trusttunnel-admin-bot/.env}"
TT_DATA_DIR="${TT_DATA_DIR:-/opt/trusttunnel}"

if [[ -z "$IMAGE_REF" ]]; then
  echo "Error: image_ref argument is required."
  echo "Usage: ./deploy.sh <image_ref>"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: env file not found: $ENV_FILE"
  exit 1
fi

if [[ ! -d "$TT_DATA_DIR" ]]; then
  echo "Error: TrustTunnel data directory not found: $TT_DATA_DIR"
  exit 1
fi

echo "Pulling image: $IMAGE_REF"
sudo docker pull "$IMAGE_REF"

PREVIOUS_IMAGE=""
if sudo docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  PREVIOUS_IMAGE="$(sudo docker inspect "$CONTAINER_NAME" --format '{{.Config.Image}}')"
  echo "Stopping old container: $CONTAINER_NAME"
  sudo docker rm -f "$CONTAINER_NAME" >/dev/null
fi

echo "Starting new container: $CONTAINER_NAME"
sudo docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  --env-file "$ENV_FILE" \
  -v "$TT_DATA_DIR:/opt/trusttunnel" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$IMAGE_REF" >/dev/null

sleep 2

if ! sudo docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "New container failed to start."
  sudo docker logs --tail=100 "$CONTAINER_NAME" || true

  if [[ -n "$PREVIOUS_IMAGE" ]]; then
    echo "Rolling back to previous image: $PREVIOUS_IMAGE"
    sudo docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      --restart unless-stopped \
      --env-file "$ENV_FILE" \
      -v "$TT_DATA_DIR:/opt/trusttunnel" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      "$PREVIOUS_IMAGE" >/dev/null
  fi

  exit 1
fi

echo "Deployment successful."
sudo docker ps --filter "name=$CONTAINER_NAME"
sudo docker logs --tail=50 "$CONTAINER_NAME"
