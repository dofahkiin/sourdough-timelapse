#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/hls}"

WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
FPS="${FPS:-30}"
BITRATE="${BITRATE:-2500000}"
SEGMENT_TIME="${SEGMENT_TIME:-1}"
LIST_SIZE="${LIST_SIZE:-4}"
LENS_POSITION="${LENS_POSITION:-6.0}"

mkdir -p "$OUT_DIR"

command -v rpicam-vid >/dev/null 2>&1 || {
  echo "Error: rpicam-vid not found. Install rpicam-apps first." >&2
  exit 1
}

command -v ffmpeg >/dev/null 2>&1 || {
  echo "Error: ffmpeg not found." >&2
  exit 1
}

# Remove stale output before starting a fresh live playlist.
find "$OUT_DIR" -maxdepth 1 -type f \
  \( -name 'live*.ts' -o -name 'live.m3u8' \) \
  -delete

echo "Starting HLS stream in $OUT_DIR"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Framerate: ${FPS} fps"
echo "Bitrate: ${BITRATE} bps"
echo "Lens position: ${LENS_POSITION}"

rpicam-vid \
  --timeout 0 \
  --nopreview \
  --inline \
  --autofocus-mode manual \
  --lens-position "$LENS_POSITION" \
  --width "$WIDTH" \
  --height "$HEIGHT" \
  --framerate "$FPS" \
  --bitrate "$BITRATE" \
  --codec h264 \
  -o - \
  | ffmpeg -hide_banner -loglevel error \
      -fflags nobuffer \
      -flags low_delay \
      -f h264 \
      -i - \
      -c copy \
      -f hls \
      -hls_time "$SEGMENT_TIME" \
      -hls_list_size "$LIST_SIZE" \
      -hls_flags delete_segments+append_list+independent_segments+omit_endlist \
      -hls_segment_filename "$OUT_DIR/live%03d.ts" \
      "$OUT_DIR/live.m3u8"
