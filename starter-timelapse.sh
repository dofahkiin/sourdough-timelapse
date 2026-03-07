#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Timelapse script for Raspberry Pi Camera Module 3
# Normal mode:
#   - intended for systemd timer start around START_TIME
#   - captures until END_TIME
#
# Test mode:
#   - ignores START_TIME / END_TIME / GRACE_SEC
#   - runs immediately for a short test
# =========================================================

# ---- Mode ----
TEST_MODE="${TEST_MODE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Normal mode settings ----
RES_W=2304
RES_H=1296

START_TIME="08:00:00"
END_TIME="16:00:00"

FPS=24
OUT_SECONDS=60

# If the timer starts a little late, still run. If it's later than this, skip.
GRACE_SEC=120

# Override with env var BASE_DIR if needed.
BASE_DIR="${BASE_DIR:-$SCRIPT_DIR/timelapse}"
DELETE_FRAMES_AFTER_RENDER=1

# ---- Camera settings ----
# rpicam timeouts accept units like "ms" and "s".
CAPTURE_TIMEOUT="4s"

# Leave empty to autofocus each shot.
# Example manual values:
#   0.0 = infinity
#   2.0 = about 0.5 m
#   3.3 = about 0.3 m
# Fixed from your focus test set: manual_lp_4_5.jpg looked best.
LENS_POSITION="4.5"

# AF tuning for close subject captures (starter jar/container).
AUTOFOCUS_RANGE="macro"
AUTOFOCUS_SPEED="normal"
# 0,0,0,0 means full frame. Change to e.g. 0.30,0.30,0.40,0.40 if needed.
AUTOFOCUS_WINDOW="0,0,0,0"

# Retry autofocus and keep the sharpest frame by FocusFoM metadata.
FOCUS_RETRIES=3
FOCUS_MIN_FOM=3350

# Leave empty for auto white balance.
# To lock white balance later, set something like:
# AWB_GAINS="1.9,1.5"
AWB_GAINS=""

# Optional fixed exposure settings. Leave empty for automatic exposure/gain.
SHUTTER_US=""
GAIN=""

# ---- Test mode settings ----
# Used only when TEST_MODE=1
TEST_RES_W=2304
TEST_RES_H=1296
TEST_FRAMES=10
TEST_INTERVAL_SEC=3
TEST_FPS=5
TEST_DELETE_FRAMES_AFTER_RENDER=0
TEST_CAPTURE_TIMEOUT="1s"

# ---- Checks ----
command -v rpicam-still >/dev/null 2>&1 || {
  echo "Error: rpicam-still not found. Install rpicam-apps first." >&2
  exit 1
}

command -v ffmpeg >/dev/null 2>&1 || {
  echo "Error: ffmpeg not found." >&2
  exit 1
}

extract_focus_fom() {
  local meta_file="$1"
  if [[ -f "$meta_file" ]]; then
    awk -F= '/^FocusFoM=/{printf "%.0f\n", $2 + 0.0; found=1} END{if(!found) print 0}' "$meta_file"
  else
    echo 0
  fi
}

extract_lens_position() {
  local meta_file="$1"
  if [[ -f "$meta_file" ]]; then
    awk -F= '/^LensPosition=/{print $2; found=1} END{if(!found) print "n/a"}' "$meta_file"
  else
    echo "n/a"
  fi
}

today=$(date +%F)

if (( TEST_MODE == 1 )); then
  RES_W="$TEST_RES_W"
  RES_H="$TEST_RES_H"
  FRAMES="$TEST_FRAMES"
  interval="$TEST_INTERVAL_SEC"
  FPS="$TEST_FPS"
  DELETE_FRAMES_AFTER_RENDER="$TEST_DELETE_FRAMES_AFTER_RENDER"
  CAPTURE_TIMEOUT="$TEST_CAPTURE_TIMEOUT"

  run_stamp=$(date +%F_%H-%M-%S)
  OUT_BASE="$BASE_DIR/test_$run_stamp"
  FRAMES_DIR="$OUT_BASE/frames"
  OUT_MP4="$OUT_BASE/timelapse_test_${FRAMES}frames_${interval}s_${FPS}fps.mp4"

  mkdir -p "$FRAMES_DIR"

  echo "TEST_MODE=1"
  echo "Capturing $FRAMES frames, every ${interval}s"
  echo "Resolution: ${RES_W}x${RES_H}"
  echo "Frames: $FRAMES_DIR"
  echo "Video:  $OUT_MP4"
else
  # ---- Derived for normal mode ----
  FRAMES=$((FPS * OUT_SECONDS))

  now_epoch=$(date +%s)
  start_epoch=$(date -d "$today $START_TIME" +%s)
  end_epoch=$(date -d "$today $END_TIME" +%s)

  # Script is designed to be started by a timer at ~START_TIME.
  # If started too early/late, skip without failing the service.
  if (( now_epoch < start_epoch )); then
    echo "Started before $START_TIME; expected systemd timer at $START_TIME. Skipping."
    exit 0
  fi

  if (( now_epoch > start_epoch + GRACE_SEC )); then
    echo "Started too late (now: $(date), expected: $START_TIME +/- ${GRACE_SEC}s). Skipping."
    exit 0
  fi

  if (( now_epoch >= end_epoch )); then
    echo "Already past end time $END_TIME; skipping."
    exit 0
  fi

  capture_seconds=$((end_epoch - start_epoch))
  if (( capture_seconds <= 0 )); then
    echo "Invalid time window: START_TIME=$START_TIME END_TIME=$END_TIME" >&2
    exit 1
  fi

  interval=$((capture_seconds / FRAMES))
  if (( interval < 1 )); then
    interval=1
  fi

  OUT_BASE="$BASE_DIR/$today"
  FRAMES_DIR="$OUT_BASE/frames"
  OUT_MP4="$OUT_BASE/timelapse_${START_TIME:0:2}${START_TIME:3:2}-${END_TIME:0:2}${END_TIME:3:2}_${OUT_SECONDS}s_${FPS}fps.mp4"

  mkdir -p "$FRAMES_DIR"

  echo "Window: $(date -d "@$start_epoch") -> $(date -d "@$end_epoch")"
  echo "Capturing $FRAMES frames, every ${interval}s"
  echo "Resolution: ${RES_W}x${RES_H}"
  echo "Frames: $FRAMES_DIR"
  echo "Video:  $OUT_MP4"
fi

cd "$FRAMES_DIR"
trap 'echo "Interrupted"; exit 1' INT TERM

capture_frame() {
  local fname="$1"
  local index="$2"
  local attempt
  local attempts="$FOCUS_RETRIES"
  local best_fom=-1
  local best_img=""
  local best_meta=""
  local out_ts
  local prefix="$FRAMES_DIR/.tmp_capture_${index}_$$"

  if [[ -n "$LENS_POSITION" || "$FOCUS_RETRIES" -lt 1 ]]; then
    attempts=1
  fi

  for ((attempt=1; attempt<=attempts; attempt++)); do
    local img="${prefix}_a${attempt}.jpg"
    local meta="${prefix}_a${attempt}.txt"

    camera_args=(
      --width "$RES_W"
      --height "$RES_H"
      --nopreview
      --timeout "$CAPTURE_TIMEOUT"
      --metadata "$meta"
      --metadata-format txt
    )

    if [[ -n "$LENS_POSITION" ]]; then
      camera_args+=(
        --autofocus-mode manual
        --lens-position "$LENS_POSITION"
      )
    else
      camera_args+=(
        --autofocus-mode auto
        --autofocus-on-capture
        --autofocus-range "$AUTOFOCUS_RANGE"
        --autofocus-speed "$AUTOFOCUS_SPEED"
        --autofocus-window "$AUTOFOCUS_WINDOW"
      )
    fi

    if [[ -n "$AWB_GAINS" ]]; then
      camera_args+=(
        --awbgains "$AWB_GAINS"
      )
    fi

    if [[ -n "$SHUTTER_US" ]]; then
      camera_args+=(
        --shutter "$SHUTTER_US"
      )
    fi

    if [[ -n "$GAIN" ]]; then
      camera_args+=(
        --gain "$GAIN"
      )
    fi

    rpicam-still "${camera_args[@]}" -o "$img"

    local fom
    fom=$(extract_focus_fom "$meta")
    if (( fom > best_fom )); then
      best_fom="$fom"
      best_img="$img"
      best_meta="$meta"
    fi

    if [[ -z "$LENS_POSITION" && "$fom" -ge "$FOCUS_MIN_FOM" ]]; then
      break
    fi
  done

  if [[ -z "$best_img" ]]; then
    echo "Failed to capture frame $fname" >&2
    exit 1
  fi

  mv -f -- "$best_img" "$fname"
  out_ts=$(date +%F\ %T)
  echo "$out_ts $fname attempts=$attempt best_fom=$best_fom lens=$(extract_lens_position "$best_meta")" >> "$OUT_BASE/focus.log"

  rm -f -- "${prefix}"_a*.jpg "${prefix}"_a*.txt || true
}

for ((i=0; i<FRAMES; i++)); do
  if (( TEST_MODE == 0 )); then
    target=$((start_epoch + i*interval))
    now=$(date +%s)
    if (( target > now )); then
      sleep $((target - now))
    fi
  else
    if (( i > 0 )); then
      sleep "$interval"
    fi
  fi

  printf -v fname "frame%06d.jpg" "$i"
  capture_frame "$fname" "$i"
  echo "Captured $fname ($((i + 1))/$FRAMES)"
done

echo "Encoding MP4..."
ffmpeg -hide_banner -loglevel error \
  -framerate "$FPS" -start_number 0 -i frame%06d.jpg \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -preset slow \
  "$OUT_MP4"

echo "Render complete: $OUT_MP4"

if (( DELETE_FRAMES_AFTER_RENDER == 1 )); then
  if [[ -n "${FRAMES_DIR:-}" && "$FRAMES_DIR" == "$OUT_BASE/frames" ]] || [[ -n "${FRAMES_DIR:-}" && "$FRAMES_DIR" == "$BASE_DIR/"test_*"/frames" ]]; then
    echo "Deleting frames directory: $FRAMES_DIR"
    rm -rf -- "$FRAMES_DIR"
  else
    echo "Refusing to delete frames: unexpected FRAMES_DIR='$FRAMES_DIR'" >&2
    exit 1
  fi
fi

echo "Done."
