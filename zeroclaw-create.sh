#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-ghcr.io/zeroclaw-labs/zeroclaw:debian}"

ask() { local p="$1" d="$2" a; read -rp "$p [$d]: " a; printf '%s' "${a:-$d}"; }

command -v docker >/dev/null || { echo "ERROR: docker not found"; exit 1; }

echo "===================================================="
echo "  ZeroClaw assistant installer"
echo "===================================================="
echo

NAME="$(ask 'Instance name' 'default')"
INSTANCE="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
[ -n "$INSTANCE" ] || INSTANCE="default"
TARGET="/opt/zeroclaw/${INSTANCE}"
PROJECT="$INSTANCE"

echo
echo "Expose the gateway on which host interface?"
echo "  1) 127.0.0.1   this VM only (reach it via an SSH tunnel)"
echo "  2) 0.0.0.0     all interfaces / LAN"
case "$(ask 'Choose 1 or 2' '2')" in
  1) BIND_IP="127.0.0.1" ;;
  *) BIND_IP="0.0.0.0" ;;
esac

PORT="$(ask 'Port' '42617')"

case "$(ask 'Include the web dashboard? (y/n)' 'y')" in
  [Yy]*) DASHBOARD=1 ;;
  *)     DASHBOARD=0 ;;
esac

echo
echo "==> Pulling ${IMAGE_TAG} ..."
docker pull -q "$IMAGE_TAG" >/dev/null
IMAGE_REF="$(docker image inspect "$IMAGE_TAG" --format '{{index .RepoDigests 0}}')"
[ -n "$IMAGE_REF" ] || IMAGE_REF="$IMAGE_TAG"
VERSION="$(docker run --rm --entrypoint zeroclaw "$IMAGE_REF" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
echo "==> ZeroClaw v${VERSION:-unknown}"

mkdir -p "$TARGET/data"

WEB_VOLUME=""
WEB_ENV=""
if [ "$DASHBOARD" = "1" ]; then
  [ -n "$VERSION" ] || { echo "ERROR: could not detect version for the dashboard"; exit 1; }
  echo "==> Fetching web dashboard v${VERSION} ..."
  rm -rf "$TARGET/web.new"; mkdir -p "$TARGET/web.new"
  curl -fsSL "https://github.com/zeroclaw-labs/zeroclaw/releases/download/v${VERSION}/zeroclaw-x86_64-unknown-linux-gnu.tar.gz" | tar -xz --strip-components=2 -C "$TARGET/web.new" web/dist
  test -f "$TARGET/web.new/index.html" || { echo "ERROR: dashboard download failed"; exit 1; }
  rm -rf "$TARGET/web"; mv "$TARGET/web.new" "$TARGET/web"
  WEB_VOLUME=$'\n      - ./web:/web:ro'
  WEB_ENV=$'\n      ZEROCLAW_WEB_DIST_DIR: "/web"'
fi

echo "==> Writing ${TARGET}/docker-compose.yml ..."
cat > "$TARGET/docker-compose.yml" <<YAML
name: ${PROJECT}
services:
  zeroclaw:
    image: ${IMAGE_REF}
    restart: unless-stopped
    ports:
      - "${BIND_IP}:${PORT}:42617"
    volumes:
      - ./data:/zeroclaw-data${WEB_VOLUME}
    environment:
      ZEROCLAW_GATEWAY_HOST: "0.0.0.0"
      ZEROCLAW_ALLOW_PUBLIC_BIND: "1"${WEB_ENV}
    depends_on:
      data-init:
        condition: service_completed_successfully
  data-init:
    image: busybox
    restart: "no"
    volumes:
      - ./data:/zeroclaw-data
    command: ["chmod", "777", "/zeroclaw-data"]
YAML

echo "==> Starting ${PROJECT} ..."
( cd "$TARGET" && docker compose up -d )

if [ -t 0 ] && [ -t 1 ]; then
  echo
  echo "==> Onboarding ${PROJECT} ..."
  ( cd "$TARGET" && docker compose exec zeroclaw zeroclaw onboard ) || true
  ( cd "$TARGET" && docker compose restart zeroclaw >/dev/null 2>&1 ) || true
else
  echo "==> No TTY; run onboarding later with:"
  echo "    cd ${TARGET} && docker compose exec zeroclaw zeroclaw onboard"
fi

sleep 3
CODE="$( ( cd "$TARGET" && docker compose logs --no-color 2>&1 ) | grep -oE 'X-Pairing-Code: [0-9]+' | tail -1 || true)"
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "===================================================="
echo "  Instance:       ${INSTANCE}  (${TARGET})"
if [ "$BIND_IP" = "127.0.0.1" ]; then
  echo "  URL (VM-local): http://127.0.0.1:${PORT}/"
  echo "  Tunnel:         ssh -L ${PORT}:127.0.0.1:${PORT} <user>@${IP:-<vm-ip>}"
else
  echo "  URL:            http://${IP:-<vm-ip>}:${PORT}/"
fi
[ -n "$CODE" ] && echo "  ${CODE}"
echo "===================================================="
