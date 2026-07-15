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
SEAM_SSIM_THRESHOLD=0.99
FULL_MAX_MB=20
FULL_TARGET_MB=18
FULL_MAX_HEIGHT=1080

is_video() { case "${1,,}" in *.mp4 | *.webm | *.mov | *.mkv) return 0 ;; *) return 1 ;; esac; }
is_image() { case "${1,,}" in *.jpg | *.jpeg | *.png | *.webp) return 0 ;; *) return 1 ;; esac; }
is_audio() { case "${1,,}" in *.mp3 | *.ogg | *.wav | *.m4a | *.flac | *.opus) return 0 ;; *) return 1 ;; esac; }

version_for() { sha1sum "$1" | cut -c1-8; }

LICENSES_FILE="$REPO_DIR/licenses.json"
license_for() {
  local id="$1"
  [[ -f "$LICENSES_FILE" ]] || { printf ''; return; }
  jq -r --arg id "$id" '.[$id] // empty' "$LICENSES_FILE"
}

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

downscale_filter() { printf "scale=-2:'min(ih\\,%d)':flags=lanczos" "$FULL_MAX_HEIGHT"; }

full_exceeds_limit() { [[ "$(stat -c%s "$1")" -gt $((FULL_MAX_MB * 1024 * 1024)) ]]; }

bitrate_for_target() {
  LC_ALL=C awk -v d="$1" -v mb="$FULL_TARGET_MB" 'BEGIN{printf "%d", (mb*8192/d)-64}'
}

cap_full_size() {
  local full="$1" d kbps tmp log
  full_exceeds_limit "$full" || return 0
  d="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$full")"
  kbps="$(bitrate_for_target "$d")"
  tmp="$(mktemp -u).mp4"
  log="$(mktemp -u)"
  ffmpeg -y -i "$full" -an -c:v libx264 -preset slow -b:v "${kbps}k" -pass 1 -passlogfile "$log" -pix_fmt yuv420p -f mp4 /dev/null </dev/null >/dev/null 2>&1
  ffmpeg -y -i "$full" -an -c:v libx264 -preset slow -b:v "${kbps}k" -pass 2 -passlogfile "$log" -pix_fmt yuv420p -movflags +faststart "$tmp" </dev/null >/dev/null 2>&1
  mv -f "$tmp" "$full"
  rm -f "${log}"* 2>/dev/null || true
  printf '  capped ~%sMB @%dkbps: %s\n' "$FULL_TARGET_MB" "$kbps" "$(basename "$full")" >&2
}

make_seamless_full() {
  local src="$1" out="$2" x="$3" d off
  d="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")"
  off="$(LC_ALL=C awk -v d="$d" -v x="$x" 'BEGIN{printf "%.3f", d-2*x}')"
  ffmpeg -y -i "$src" -filter_complex \
    "[0]split[main][pre];[pre]trim=0:${x},setpts=PTS-STARTPTS[pre2];[main]trim=${x}:${d},setpts=PTS-STARTPTS[main2];[main2][pre2]xfade=transition=fade:duration=${x}:offset=${off},$(downscale_filter),format=yuv420p[v]" \
    -map "[v]" -an -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -movflags +faststart "$out" </dev/null >/dev/null 2>&1
}

crossfade_len_for() {
  local d="$1"
  LC_ALL=C awk -v d="$d" -v x="$CROSSFADE_SECONDS" 'BEGIN{m=d/3.0; if (x<m) print x; else printf "%.3f", m}'
}

make_plain_full() {
  local src="$1" out="$2" h
  h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$src")"
  if [[ "${h:-0}" -le "$FULL_MAX_HEIGHT" ]]; then
    ffmpeg -y -i "$src" -an -c:v copy -movflags +faststart "$out" </dev/null >/dev/null 2>&1
  else
    ffmpeg -y -i "$src" -an -vf "$(downscale_filter),format=yuv420p" -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -movflags +faststart "$out" </dev/null >/dev/null 2>&1
  fi
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
    dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")"
    xlen="$(crossfade_len_for "$dur")"
    need_x="$(LC_ALL=C awk -v s="$ssim" -v t="$SEAM_SSIM_THRESHOLD" 'BEGIN{print (s+0 < t)?1:0}')"
    if [[ "$need_x" == "1" ]]; then
      make_seamless_full "$src" "$full" "$xlen"
      printf 'crossfade x=%s (seam %s): %s\n' "$xlen" "$ssim" "$id" >&2
    else
      make_plain_full "$src" "$full"
      printf 'kept          (seam %s): %s\n' "$ssim" "$id" >&2
    fi
    cap_full_size "$full"
    make_video_preview "$full" "$PREVIEW_DIR/$id.mp4"
    make_video_poster "$full" "$PREVIEW_DIR/$id.jpg"
    ver="$(version_for "$full")"
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" \
      '{id:$id,type:"video",name:$name,preview:($base+"/preview/"+$id+".mp4?v="+$ver),full:($base+"/full/"+$id+".mp4?v="+$ver),poster:($base+"/preview/"+$id+".jpg?v="+$ver),version:$ver}')"
  elif is_image "$base"; then
    full="$FULL_DIR/$id.$ext"
    cp -f "$src" "$full"
    make_image_preview "$full" "$PREVIEW_DIR/$id.jpg"
    ver="$(version_for "$full")"
    if full_exceeds_limit "$full"; then
      printf 'AVISO: imagem %s tem >%sMB; jsDelivr recusa, reduza o arquivo\n' "$id" "$FULL_MAX_MB" >&2
    fi
    printf 'image             : %s\n' "$id" >&2
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" --arg ext "$ext" \
      '{id:$id,type:"image",name:$name,preview:($base+"/preview/"+$id+".jpg?v="+$ver),full:($base+"/full/"+$id+"."+$ext+"?v="+$ver),version:$ver}')"
  elif is_audio "$base"; then
    full="$FULL_DIR/$id.mp3"
    ffmpeg -y -i "$src" -vn -c:a libmp3lame -q:a 4 "$full" </dev/null >/dev/null 2>&1
    ver="$(version_for "$full")"
    lic="$(license_for "$id")"
    if full_exceeds_limit "$full"; then
      printf 'AVISO: audio %s tem >%sMB; jsDelivr recusa, reduza o bitrate\n' "$id" "$FULL_MAX_MB" >&2
    fi
    printf 'audio             : %s\n' "$id" >&2
    asset="$(jq -n --arg id "$id" --arg name "$name" --arg ver "$ver" --arg base "$BASE_URL" --arg lic "$lic" \
      '{id:$id,type:"sound",name:$name,icon:$id,full:($base+"/full/"+$id+".mp3?v="+$ver),license:$lic,version:$ver}')"
  else
    printf 'skip (unknown type): %s\n' "$base" >&2
    continue
  fi

  assets="$(jq --argjson a "$asset" '. + [$a]' <<<"$assets")"
done

jq -n --argjson assets "$assets" '{schemaVersion:1, assets:$assets}' >"$MANIFEST_FILE"
printf 'manifest: %s (%s assets)\n' "$MANIFEST_FILE" "$(jq '.assets|length' "$MANIFEST_FILE")"
