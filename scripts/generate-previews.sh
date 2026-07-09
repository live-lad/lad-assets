#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_DIR/source"
FULL_DIR="$REPO_DIR/full"
PREVIEW_DIR="$REPO_DIR/preview"
LABELS_FILE="$REPO_DIR/labels.json"
MANIFEST_FILE="$REPO_DIR/manifest.json"
BASE_URL="https://cdn.jsdelivr.net/gh/live-lad/lad-assets@main"

PREVIEW_WIDTH=640
IMAGE_PREVIEW_WIDTH=1280
CROSSFADE_SECONDS=1.0
SEAM_SSIM_THRESHOLD=0.7

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

seam_ssim() {
  local src="$1" tmp s
  tmp="$(mktemp -d)"
  ffmpeg -y -i "$src" -vf "select=eq(n\,0)" -vframes 1 "$tmp/a.png" </dev/null >/dev/null 2>&1 || true
  ffmpeg -y -sseof -0.06 -i "$src" -vframes 1 "$tmp/b.png" </dev/null >/dev/null 2>&1 || true
  s="$(ffmpeg -i "$tmp/a.png" -i "$tmp/b.png" -filter_complex ssim -f null - 2>&1 | grep -o 'All:[0-9.]*' | head -1 | cut -d: -f2)"
  rm -rf "$tmp"
  printf '%s' "${s:-1}"
}

make_seamless_full() {
  local src="$1" out="$2" d cut
  d="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")"
  cut="$(LC_ALL=C awk -v d="$d" -v x="$CROSSFADE_SECONDS" 'BEGIN{printf "%.3f", d-x}')"
  ffmpeg -y -i "$src" -filter_complex \
    "[0]split[body][tail];[tail]trim=start=${cut},setpts=PTS-STARTPTS,format=yuva420p,fade=t=out:st=0:d=${CROSSFADE_SECONDS}:alpha=1[tf];[body]trim=0:${cut},setpts=PTS-STARTPTS[main];[main][tf]overlay,format=yuv420p[v]" \
    -map "[v]" -an -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -movflags +faststart "$out" </dev/null >/dev/null 2>&1
}

copy_full() {
  ffmpeg -y -i "$1" -an -c:v copy -movflags +faststart "$2" </dev/null >/dev/null 2>&1
}

make_video_preview() {
  ffmpeg -y -i "$1" -an -vf "scale=$PREVIEW_WIDTH:-2" -c:v libx264 -preset veryfast -crf 30 \
    -pix_fmt yuv420p -movflags +faststart "$2" </dev/null >/dev/null 2>&1
}

make_video_poster() {
  ffmpeg -y -ss 1 -i "$1" -vframes 1 -vf "scale=$PREVIEW_WIDTH:-2" -q:v 4 "$2" </dev/null >/dev/null 2>&1
}

make_image_preview() {
  ffmpeg -y -i "$1" -vf "scale='min($IMAGE_PREVIEW_WIDTH,iw)':-2" -q:v 4 "$2" </dev/null >/dev/null 2>&1
}

mkdir -p "$SOURCE_DIR" "$FULL_DIR" "$PREVIEW_DIR"
assets='[]'
shopt -s nullglob

for src in "$SOURCE_DIR"/*; do
  base="$(basename "$src")"
  [[ "$base" == ".gitkeep" ]] && continue
  ext="${base##*.}"
  id="${base%.*}"
  name="$(label_for "$id")"

  if is_video "$base"; then
    full="$FULL_DIR/$id.mp4"
    ssim="$(seam_ssim "$src")"
    need_x="$(LC_ALL=C awk -v s="$ssim" -v t="$SEAM_SSIM_THRESHOLD" 'BEGIN{print (s+0 < t)?1:0}')"
    if [[ "$need_x" == "1" ]]; then
      make_seamless_full "$src" "$full"
      printf 'crossfade  (seam %s): %s\n' "$ssim" "$id" >&2
    else
      copy_full "$src" "$full"
      printf 'kept       (seam %s): %s\n' "$ssim" "$id" >&2
    fi
    make_video_preview "$full" "$PREVIEW_DIR/$id.mp4"
    make_video_poster "$full" "$PREVIEW_DIR/$id.jpg"
    ver="$(version_for "$full")"
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" \
      '{id:$id,type:"video",name:$name,preview:($base+"/preview/"+$id+".mp4"),full:($base+"/full/"+$id+".mp4"),poster:($base+"/preview/"+$id+".jpg"),version:$ver}')"
  elif is_image "$base"; then
    full="$FULL_DIR/$id.$ext"
    cp -f "$src" "$full"
    make_image_preview "$full" "$PREVIEW_DIR/$id.jpg"
    ver="$(version_for "$full")"
    printf 'image             : %s\n' "$id" >&2
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" --arg ext "$ext" \
      '{id:$id,type:"image",name:$name,preview:($base+"/preview/"+$id+".jpg"),full:($base+"/full/"+$id+"."+$ext),version:$ver}')"
  else
    printf 'skip (unknown type): %s\n' "$base" >&2
    continue
  fi

  assets="$(jq --argjson a "$asset" '. + [$a]' <<<"$assets")"
done

jq -n --argjson assets "$assets" '{schemaVersion:1, assets:$assets}' >"$MANIFEST_FILE"
printf 'manifest: %s (%s assets)\n' "$MANIFEST_FILE" "$(jq '.assets|length' "$MANIFEST_FILE")"
