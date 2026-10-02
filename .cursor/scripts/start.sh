#!/usr/bin/env bash
# Start the published SQ Web Viewer backend.
#
# The release is an Electron shell around this ASP.NET server. Cloud agents
# run the server directly so the web UI and tile API are available without a
# desktop session. Local access does not require the desktop auth token.

set -euo pipefail

PREFIX="${SQWV_PREFIX:-$HOME/.sq-web-viewer}"
APP_DIR="$PREFIX/app"
SLIDES_DIR="${SQWV_SLIDES_DIR:-$PREFIX/slides}"
APP_DATA="${SQWV_APP_DATA:-$PREFIX/appdata}"
HOST="${SQWV_HOST:-0.0.0.0}"
PORT="${SQWV_PORT:-8080}"

log() { printf '[start] %s\n' "$*"; }

if curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
  log "SQ Web Viewer is already listening on port ${PORT}"
  exit 0
fi

backend_dir="$(find "$APP_DIR" -maxdepth 4 -type d -name backend -path '*/resources/backend' -print -quit || true)"
if [[ -z "$backend_dir" || ! -x "$backend_dir/SqWebViewer" ]]; then
  echo "[start] ERROR: extracted build not found under $APP_DIR. Run bash .cursor/scripts/install.sh first." >&2
  exit 1
fi

mkdir -p "$SLIDES_DIR" "$APP_DATA"
res_dir="$(dirname "$backend_dir")"

export ASPNETCORE_URLS="http://${HOST}:${PORT}"
export SQWEBVIEWER_NATIVE_ROOT="${res_dir}/native"
export SQWEBVIEWER_APP_DATA="$APP_DATA"
export DOTNET_CLI_HOME="${APP_DATA}/.dotnet-cli-home"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1
export Slides__SlidesFolder="$SLIDES_DIR"
export Slides__EnableOpenSlide=true
export App__RequireToken=false

log "Serving SQ Web Viewer on http://${HOST}:${PORT}"
log "Slides folder: $SLIDES_DIR"
cd "$backend_dir"
exec ./SqWebViewer
