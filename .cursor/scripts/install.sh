#!/usr/bin/env bash
#
# Cloud Agent install step for the SQ Web Viewer release repository.
#
# This repository ships no application source. The "application" lives in the
# published GitHub Releases as a Linux x64 build. To give an agent a working,
# runnable copy of the product, this script downloads the latest release's
# portable tarball, verifies it against the published SHA-256 checksum file,
# and extracts it into a stable location under $HOME.
#
# It is idempotent: if the currently extracted build already matches the latest
# published tag and its checksum verifies, it exits without re-downloading.

set -euo pipefail

REPO="${SQWV_REPO:-Ethan7431/sq-web-viewer-releases}"
PREFIX="${SQWV_PREFIX:-$HOME/.sq-web-viewer}"
DOWNLOAD_DIR="$PREFIX/download"
APP_DIR="$PREFIX/app"
SLIDES_DIR="${SQWV_SLIDES_DIR:-$PREFIX/slides}"
STATE_FILE="$PREFIX/installed-tag"

log() { printf '[install] %s\n' "$*"; }

mkdir -p "$DOWNLOAD_DIR" "$APP_DIR" "$SLIDES_DIR"

# --- Resolve the latest release via the public GitHub API -------------------
API="https://api.github.com/repos/$REPO/releases/latest"
AUTH=()
if [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
  AUTH=(-H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}")
fi

log "Querying latest release of $REPO"
RELEASE_JSON="$(curl -fsSL "${AUTH[@]}" -H "Accept: application/vnd.github+json" "$API")"

# Parse tag + the two asset URLs we need (portable tarball + its checksum file).
read -r TAG TARBALL_URL SUMS_URL < <(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
tag = data.get("tag_name", "")
tarball = sums = ""
for a in data.get("assets", []):
    name = a.get("name", "")
    url = a.get("browser_download_url", "")
    if name.endswith("linux-x64.tar.gz"):
        tarball = url
    elif name.endswith("linux-x64-SHA256SUMS.txt"):
        sums = url
print(tag, tarball, sums)
PY
)

if [[ -z "$TAG" || -z "$TARBALL_URL" || -z "$SUMS_URL" ]]; then
  echo "[install] ERROR: could not resolve latest Linux x64 release assets for $REPO" >&2
  exit 1
fi
log "Latest release: $TAG"

TARBALL_NAME="$(basename "$TARBALL_URL")"
SUMS_NAME="$(basename "$SUMS_URL")"
TARBALL_PATH="$DOWNLOAD_DIR/$TARBALL_NAME"
SUMS_PATH="$DOWNLOAD_DIR/$SUMS_NAME"

# --- Idempotence: skip when the extracted build is already current ----------
if [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$TAG" ]] \
   && find "$APP_DIR" -maxdepth 5 -name SqWebViewer -type f 2>/dev/null | grep -q .; then
  log "Build $TAG already installed and extracted; nothing to do."
else
  log "Downloading $SUMS_NAME"
  curl -fsSL "${AUTH[@]}" -o "$SUMS_PATH" "$SUMS_URL"

  # Reuse an existing tarball if it already matches the published checksum.
  if [[ -f "$TARBALL_PATH" ]] && (cd "$DOWNLOAD_DIR" && grep " $TARBALL_NAME\$" "$SUMS_NAME" | sha256sum -c - >/dev/null 2>&1); then
    log "Reusing verified $TARBALL_NAME"
  else
    log "Downloading $TARBALL_NAME (this is the full release build; it may take a moment)"
    curl -fSL "${AUTH[@]}" -o "$TARBALL_PATH" "$TARBALL_URL"
  fi

  log "Verifying SHA-256 checksum"
  (cd "$DOWNLOAD_DIR" && grep " $TARBALL_NAME\$" "$SUMS_NAME" | sha256sum -c -)

  log "Extracting into $APP_DIR"
  rm -rf "${APP_DIR:?}/"*
  tar -xzf "$TARBALL_PATH" -C "$APP_DIR"

  echo "$TAG" > "$STATE_FILE"
  log "Installed $TAG"
fi

# --- Best-effort: seed a viewable demo slide so the viewer has content ------
# Uses a synthetic OpenSlide-compatible tiled TIFF. This is optional; a failure
# here (e.g. no network for pip) must not fail environment setup.
if ! find "$SLIDES_DIR" -maxdepth 1 -type f \
      \( -iname '*.tif' -o -iname '*.tiff' -o -iname '*.svs' \) 2>/dev/null | grep -q .; then
  log "Seeding a synthetic demo slide (best-effort)"
  if python3 -c "import numpy" >/dev/null 2>&1 \
     || python3 -m pip install --user --quiet numpy >/dev/null 2>&1; then
    python3 -m pip install --user --quiet tifffile >/dev/null 2>&1 || true
    if python3 -c "import numpy, tifffile" >/dev/null 2>&1; then
      SQWV_SLIDES_DIR="$SLIDES_DIR" python3 "$(dirname "$0")/make-demo-slide.py" || \
        log "demo slide generation skipped"
    else
      log "tifffile unavailable; skipping demo slide"
    fi
  else
    log "numpy unavailable; skipping demo slide"
  fi
fi

log "Done. Run the viewer with: bash .cursor/scripts/run-viewer.sh"
