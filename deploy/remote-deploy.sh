#!/bin/sh
# Runs ON the server after the files were copied (called by .github/workflows/deploy-web.yml).
set -eu
cd "$(dirname "$0")"
MODE="${1:-docker}"
if [ "$MODE" = "docker" ]; then
  docker compose up -d --build --remove-orphans
  docker image prune -f >/dev/null 2>&1 || true
else
  sudo systemctl restart denthub-brush
fi
# Wait until the service answers.
for i in $(seq 1 20); do
  if curl -fsS "http://127.0.0.1:${BRUSH_PORT:-8090}/healthz" >/dev/null 2>&1; then echo "DentHub-Brush web is up"; exit 0; fi
  sleep 2
done
echo "DentHub-Brush web did not start" >&2
exit 1
