#!/usr/bin/env bash
# Генерирует TSV-строки для всех пользователей TrustTunnel в запущенном контейнере:
# <username>\t<tt:// ссылка>\t<ссылка на страницу с QR-кодом>.
#
# Использование:
#   ./generate-tt-links-with-qr.sh [output_file]
#
# Переопределение через переменные окружения:
#   CONTAINER_NAME=trusttunnel ENDPOINT_ADDRESS=tt.example.com:443 ./generate-tt-links-with-qr.sh
#
# Вариант с .env файлом:
#   set -a; source .env; set +a
#   ./generate-tt-links-with-qr.sh /tmp/tt-links-with-qr.tsv
#
# Как выдать права на запуск (Linux/macOS):
#   chmod +x ./generate-tt-links-with-qr.sh
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-trusttunnel}"
ENDPOINT_ADDRESS="${ENDPOINT_ADDRESS:-tt.example.com:443}"
OUTPUT_FILE="${1:-}"

generate_rows() {
  sudo docker exec "$CONTAINER_NAME" sh -lc "awk -F'\"' '/^[[:space:]]*username[[:space:]]*=/{print \$2}' /trusttunnel_endpoint/credentials.toml" \
  | while IFS= read -r user; do
      out="$(sudo docker exec "$CONTAINER_NAME" /bin/trusttunnel_endpoint \
        /trusttunnel_endpoint/vpn.toml /trusttunnel_endpoint/hosts.toml \
        -c "$user" -a "$ENDPOINT_ADDRESS")"

      tt_link="$(printf '%s\n' "$out" | awk '/^tt:\/\//{print; exit}')"
      qr_link="$(printf '%s\n' "$out" | awk '/https:\/\/trusttunnel\.org\/qr\.html#tt=/{print; exit}')"

      printf '%s\t%s\t%s\n' "$user" "$tt_link" "$qr_link"
    done
}

if [ -n "$OUTPUT_FILE" ]; then
  generate_rows | tee "$OUTPUT_FILE"
else
  generate_rows
fi
