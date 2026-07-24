#!/usr/bin/env bash
# Generate + sync grid/modal derivatives for the aleph image collection.
#
# Source of truth: the aleph folder on the T7 SSD. For every image there,
# this script maintains two WebP derivatives (skipping ones already up to date):
#   aleph-thumbs/<name>.webp   400px long edge, q75  (grid tiles)
#   aleph-display/<name>.webp  1600px long edge, q80 (modal view)
# then rclone-syncs both folders to B2, deleting remote orphans.
#
# Derivatives for images you've deleted from the source folder are pruned.
# Safe to re-run any time; only new/changed images are processed.
#
# Usage: ./make-derivatives.sh [--dry-run] [source-dir]

set -euo pipefail

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; shift; fi
SRC="${1:-/media/hweikel/aerostat/outercasmalia/aleph}"

BASE="$(dirname "$SRC")"
THUMBS="$BASE/aleph-thumbs"
DISPLAY="$BASE/aleph-display"
REMOTE="b2-outercasmalia:outercasmalia"
JOBS="$(nproc)"

if [[ ! -d "$SRC" ]]; then
  echo "ERROR: source folder not found: $SRC" >&2
  echo "Is the T7 plugged in and mounted?" >&2
  exit 1
fi

mkdir -p "$THUMBS" "$DISPLAY"
# clear leftovers from any previously interrupted run
find "$THUMBS" "$DISPLAY" -maxdepth 1 -name '.tmp-*' -delete

# ── Collect source images (top level only; skips aleph-tunes/, tags.json,
#    .osxphotos_export.db, ._* AppleDouble junk, and anything non-image)
mapfile -d '' -t IMAGES < <(
  find "$SRC" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    ! -name '._*' -printf '%f\0' | sort -z
)
echo "source images: ${#IMAGES[@]}"

# ── Figure out which derivatives are missing or stale
worklist_thumb=()
worklist_display=()
for f in "${IMAGES[@]}"; do
  [[ "$THUMBS/$f.webp"  -nt "$SRC/$f" ]] || worklist_thumb+=("$f")
  [[ "$DISPLAY/$f.webp" -nt "$SRC/$f" ]] || worklist_display+=("$f")
done
echo "to generate: ${#worklist_thumb[@]} thumbs, ${#worklist_display[@]} display"

if [[ -n "$DRY_RUN" ]]; then
  (( ${#worklist_thumb[@]} )) && printf '  would thumb: %s\n' "${worklist_thumb[@]:0:20}"
  echo "(dry run — stopping before generation and prune/sync)"
  exit 0
fi

# ── Generate in parallel. Convert writes to a hidden temp file in the same
#    dir, then an atomic mv — a crash can never leave a truncated .webp that
#    the mtime check would treat as done.
gen() {
  local size="$1" quality="$2" outdir="$3" f="$4"
  local tmp
  tmp="$(mktemp -p "$outdir" '.tmp-XXXXXX')"
  if convert "$SRC_DIR/$f" -auto-orient -strip \
       -resize "${size}x${size}>" -quality "$quality" "webp:$tmp" 2>/dev/null; then
    chmod 644 "$tmp"
    mv "$tmp" "$outdir/$f.webp"
  else
    rm -f "$tmp"
    echo "FAILED: $f" >&2
  fi
}
export -f gen
export SRC_DIR="$SRC"

if (( ${#worklist_thumb[@]} )); then
  printf '%s\0' "${worklist_thumb[@]}" \
    | xargs -0 -P "$JOBS" -I{} bash -c 'gen 400 75 "$1" "$2"' _ "$THUMBS" {}
fi
if (( ${#worklist_display[@]} )); then
  printf '%s\0' "${worklist_display[@]}" \
    | xargs -0 -P "$JOBS" -I{} bash -c 'gen 1600 80 "$1" "$2"' _ "$DISPLAY" {}
fi

# ── Prune derivatives whose source image is gone
pruned=0
for dir in "$THUMBS" "$DISPLAY"; do
  while IFS= read -r -d '' d; do
    name="$(basename "$d")"
    if [[ ! -f "$SRC/${name%.webp}" ]]; then
      rm -f "$d"
      ((pruned++)) || true
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.webp' -print0)
done
echo "pruned: $pruned orphan derivatives"

# ── Sync to B2 (deletes remote orphans to match local).
#    Long-lived caching is handled by a Cloudflare Cache Rule on
#    trove.henryweikel.net, not by upload headers (this rclone's b2
#    backend can't set Cache-Control on upload).
rclone sync "$THUMBS"  "$REMOTE/aleph-thumbs"  --exclude '.tmp-*' --progress
rclone sync "$DISPLAY" "$REMOTE/aleph-display" --exclude '.tmp-*' --progress

echo "done: $(find "$THUMBS" -type f -name '*.webp' | wc -l) thumbs, $(find "$DISPLAY" -type f -name '*.webp' | wc -l) display images in sync"
