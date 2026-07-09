#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FULL_DIR="$REPO_DIR/full"
PREVIEW_DIR="$REPO_DIR/preview"
LABELS_FILE="$REPO_DIR/labels.json"
MANIFEST_FILE="$REPO_DIR/manifest.json"
BASE_URL="https://cdn.jsdelivr.net/gh/live-lad/lad-assets@main"

PREVIEW_WIDTH=640
PREVIEW_MAX_SECONDS=8
IMAGE_PREVIEW_WIDTH=1280

is_video() { case "${1,,}" in *.mp4 | *.webm | *.mov | *.mkv) return 0 ;; *) return 1 ;; esac; }
is_image() { case "${1,,}" in *.jpg | *.jpeg | *.png | *.webp) return 0 ;; *) return 1 ;; esac; }

version_for() { sha1sum "$1" | cut -c1-8; }

label_for() {
  local id="$1" mapped
  if [[ -f "$LABELS_FILE" ]]; then
    mapped="$(jq -r --arg id "$id" '.[$id] // empty' "$LABELS_FILE")"
    if [[ -n "$mapped" ]]; then
      printf '%s' "$mapped"
      return
    fi
  fi
  printf '%s' "$id" | tr -- '-_' '  ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}; print}'
}

make_video_preview() {
  ffmpeg -y -i "$1" -t "$PREVIEW_MAX_SECONDS" -an \
    -vf "scale=$PREVIEW_WIDTH:-2" -c:v libx264 -preset veryfast -crf 30 \
    -pix_fmt yuv420p -movflags +faststart "$2" </dev/null >/dev/null 2>&1
}

make_video_poster() {
  ffmpeg -y -ss 1 -i "$1" -vframes 1 -vf "scale=$PREVIEW_WIDTH:-2" -q:v 4 "$2" </dev/null >/dev/null 2>&1
}

make_image_preview() {
  ffmpeg -y -i "$1" -vf "scale='min($IMAGE_PREVIEW_WIDTH,iw)':-2" -q:v 4 "$2" </dev/null >/dev/null 2>&1
}

assets='[]'
shopt -s nullglob

for src in "$FULL_DIR"/*; do
  base="$(basename "$src")"
  [[ "$base" == ".gitkeep" ]] && continue
  ext="${base##*.}"
  id="${base%.*}"
  ver="$(version_for "$src")"
  name="$(label_for "$id")"

  if is_video "$base"; then
    make_video_preview "$src" "$PREVIEW_DIR/$id.mp4"
    make_video_poster "$src" "$PREVIEW_DIR/$id.jpg"
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" --arg ext "$ext" \
      '{id:$id,type:"video",name:$name,preview:($base+"/preview/"+$id+".mp4"),full:($base+"/full/"+$id+"."+$ext),poster:($base+"/preview/"+$id+".jpg"),version:$ver}')"
  elif is_image "$base"; then
    make_image_preview "$src" "$PREVIEW_DIR/$id.jpg"
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" --arg ext "$ext" \
      '{id:$id,type:"image",name:$name,preview:($base+"/preview/"+$id+".jpg"),full:($base+"/full/"+$id+"."+$ext),version:$ver}')"
  else
    printf 'skip (unknown type): %s\n' "$base" >&2
    continue
  fi

  assets="$(jq --argjson a "$asset" '. + [$a]' <<<"$assets")"
  printf 'ok: %s -> %s (v%s)\n' "$base" "$name" "$ver"
done

jq -n --argjson assets "$assets" '{schemaVersion:1, assets:$assets}' >"$MANIFEST_FILE"
printf 'manifest: %s (%s assets)\n' "$MANIFEST_FILE" "$(jq '.assets|length' "$MANIFEST_FILE")"
