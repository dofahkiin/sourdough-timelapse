#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$SCRIPT_DIR/focus-shots-$(date +%F_%H-%M-%S)}"

RES_W=2304
RES_H=1296
CAPTURE_TIMEOUT="3s"

# Adjust this list if you want to test more or fewer positions.
LENS_POSITIONS=(
  2.5
  3.0
  3.3
  3.7
  4.0
  4.5
  5.0
  6.0
)

command -v rpicam-still >/dev/null 2>&1 || {
  echo "Error: rpicam-still not found. Install rpicam-apps first." >&2
  exit 1
}

mkdir -p "$OUT_DIR"

printf "name\tlens_position\tfocus_fom\texposure_us\tanalogue_gain\n" > "$OUT_DIR/summary.tsv"

extract_field() {
  local key="$1"
  local meta_file="$2"
  awk -F= -v key="$key" '$1 == key {print $2; found=1} END {if (!found) print "n/a"}' "$meta_file"
}

for lp in "${LENS_POSITIONS[@]}"; do
  tag="${lp//./_}"
  img="$OUT_DIR/manual_lp_${tag}.jpg"
  meta="$OUT_DIR/manual_lp_${tag}.txt"

  echo "Capturing lens position $lp -> $img"
  rpicam-still \
    --width "$RES_W" \
    --height "$RES_H" \
    --nopreview \
    --timeout "$CAPTURE_TIMEOUT" \
    --autofocus-mode manual \
    --lens-position "$lp" \
    --metadata "$meta" \
    --metadata-format txt \
    -o "$img"

  focus_fom="$(extract_field FocusFoM "$meta")"
  exposure_us="$(extract_field ExposureTime "$meta")"
  analogue_gain="$(extract_field AnalogueGain "$meta")"
  printf "manual_lp_%s\t%s\t%s\t%s\t%s\n" "$tag" "$lp" "$focus_fom" "$exposure_us" "$analogue_gain" >> "$OUT_DIR/summary.tsv"
done

echo
echo "Done. Review the JPG files in:"
echo "  $OUT_DIR"
echo
echo "Summary:"
column -t -s $'\t' "$OUT_DIR/summary.tsv"
