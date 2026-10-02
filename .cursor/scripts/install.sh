#!/usr/bin/env bash
# Install the latest published SQ Web Viewer Linux x64 build.
#
# This repository has no application source. The runnable product is the
# portable tarball attached to GitHub Releases. The script downloads that
# tarball, checks it against the published SHA-256 file, extracts it under
# $HOME/.sq-web-viewer, and seeds one synthetic slide so the viewer has
# something to open.

set -euo pipefail

REPO="${SQWV_REPO:-Ethan7431/sq-web-viewer-releases}"
PREFIX="${SQWV_PREFIX:-$HOME/.sq-web-viewer}"
DOWNLOAD_DIR="$PREFIX/download"
APP_DIR="$PREFIX/app"
SLIDES_DIR="${SQWV_SLIDES_DIR:-$PREFIX/slides}"
STATE_FILE="$PREFIX/installed-tag"

log() { printf '[install] %s\n' "$*"; }

mkdir -p "$DOWNLOAD_DIR" "$APP_DIR" "$SLIDES_DIR"

auth=()
token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$token" ]]; then
  auth=(-H "Authorization: Bearer ${token}")
fi

log "Querying latest release of $REPO"
release_json="$(curl -fsSL "${auth[@]}" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPO}/releases/latest")"

read -r tag tarball_url sums_url < <(printf '%s' "$release_json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
tag = data.get("tag_name") or ""
tarball = sums = ""
for asset in data.get("assets") or []:
    name = asset.get("name") or ""
    url = asset.get("browser_download_url") or ""
    if name.endswith("linux-x64.tar.gz"):
        tarball = url
    elif name.endswith("linux-x64-SHA256SUMS.txt"):
        sums = url
print(tag, tarball, sums)
')

if [[ -z "$tag" || -z "$tarball_url" || -z "$sums_url" ]]; then
  echo "[install] ERROR: latest release has no Linux x64 tarball and checksum file" >&2
  exit 1
fi
log "Latest release: $tag"

tarball_name="$(basename "$tarball_url")"
sums_name="$(basename "$sums_url")"
tarball_path="$DOWNLOAD_DIR/$tarball_name"
sums_path="$DOWNLOAD_DIR/$sums_name"

installed_bin="$(find "$APP_DIR" -maxdepth 5 -type f -name SqWebViewer -print -quit || true)"
if [[ -n "$installed_bin" && -f "$STATE_FILE" && "$(<"$STATE_FILE")" == "$tag" ]]; then
  log "Build $tag is already extracted"
else
  log "Downloading $sums_name"
  curl -fsSL "${auth[@]}" -o "$sums_path" "$sums_url"

  if [[ -f "$tarball_path" ]] && grep -F "  ${tarball_name}" "$sums_path" | (cd "$DOWNLOAD_DIR" && sha256sum -c - >/dev/null); then
    log "Reusing verified $tarball_name"
  else
    log "Downloading $tarball_name"
    tmp_path="${tarball_path}.partial"
    curl -fSL "${auth[@]}" -o "$tmp_path" "$tarball_url"
    mv "$tmp_path" "$tarball_path"
  fi

  log "Verifying SHA-256 checksum"
  grep -F "  ${tarball_name}" "$sums_path" | (cd "$DOWNLOAD_DIR" && sha256sum -c -)

  log "Extracting into $APP_DIR"
  find "$APP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  tar -xzf "$tarball_path" -C "$APP_DIR"
  printf '%s\n' "$tag" > "$STATE_FILE"
  log "Installed $tag"
fi

if ! find "$SLIDES_DIR" -maxdepth 1 -type f \( -iname '*.tif' -o -iname '*.tiff' -o -iname '*.svs' \) -print -quit | grep -q .; then
  log "Installing Python packages for the demo slide"
  if ! python3 -c "import numpy, tifffile" >/dev/null 2>&1; then
    python3 -m pip install --user --disable-pip-version-check --quiet tifffile \
      || python3 -m pip install --user --break-system-packages --disable-pip-version-check --quiet tifffile
  fi
  python3 -c "import numpy, tifffile"
  log "Generating synthetic demo slide"
  SQWV_SLIDES_DIR="$SLIDES_DIR" python3 "$(dirname "$0")/make-demo-slide.py"
fi

log "Done"
