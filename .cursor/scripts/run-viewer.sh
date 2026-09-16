#!/usr/bin/env bash
#
# Run the SQ Web Viewer backend web server (headless) from the extracted
# release build. The packaged product is an Electron desktop shell around this
# ASP.NET Core (Kestrel) server, which serves the web UI and the slide tiling
# API. Running the server directly is the display-free way to exercise and QA
# the released application in a Cloud Agent.
#
# Environment variables mirror what the Electron main process sets when it
# launches the backend (see resources/app.asar desktop/backendProcess.cjs),
# except the auth token is disabled here for convenient local access.

set -euo pipefail

PREFIX="${SQWV_PREFIX:-$HOME/.sq-web-viewer}"
APP_DIR="$PREFIX/app"
SLIDES_DIR="${SQWV_SLIDES_DIR:-$PREFIX/slides}"
APP_DATA="${SQWV_APP_DATA:-$PREFIX/appdata}"
HOST="${SQWV_HOST:-127.0.0.1}"
PORT="${SQWV_PORT:-8080}"

# Locate the extracted build (a single SQ-Web-Viewer-*-linux-x64 directory).
BACKEND_DIR="$(find "$APP_DIR" -maxdepth 4 -type d -name backend -path '*/resources/backend' 2>/dev/null | head -n1)"
if [[ -z "$BACKEND_DIR" ]]; then
  echo "[run] ERROR: no extracted build found under $APP_DIR." >&2
  echo "[run] Run 'bash .cursor/scripts/install.sh' first." >&2
  exit 1
fi
RES_DIR="$(dirname "$BACKEND_DIR")"

mkdir -p "$SLIDES_DIR" "$APP_DATA"

export ASPNETCORE_URLS="http://$HOST:$PORT"
export SQWEBVIEWER_NATIVE_ROOT="$RES_DIR/native"
export SQWEBVIEWER_APP_DATA="$APP_DATA"
export DOTNET_CLI_HOME="$APP_DATA/.dotnet-cli-home"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_NOLOGO=1
export Slides__SlidesFolder="$SLIDES_DIR"
export Slides__EnableOpenSlide=true
export App__RequireToken=false

echo "[run] Serving SQ Web Viewer on http://$HOST:$PORT (slides: $SLIDES_DIR)"
cd "$BACKEND_DIR"
exec ./SqWebViewer
