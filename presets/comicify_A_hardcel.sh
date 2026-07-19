#!/usr/bin/env bash
#
# comicify.sh — posterize / comic-book stylization pass for live-action video.
#
# Flattens colors into visible steps (posterize) with boosted saturation, while
# the footage still reads as real life. Optional dark ink outlines for a fuller
# comic look. Audio is passed through untouched; source resolution and frame
# rate are preserved.
#
# USAGE
#   ./comicify.sh                      Batch every .mp4 in INPUT_DIR -> OUTPUT_DIR
#   ./comicify.sh --preview            Dial-in mode: a few seconds from the middle
#                                      of the FIRST clip in INPUT_DIR
#   ./comicify.sh --preview clip.mp4   Preview a specific clip
#   ./comicify.sh -i in -o out         Override input/output folders
#
#   Flags may be combined, e.g.:  ./comicify.sh --preview -i raw -o styled
#
# Tune the PARAMETER BLOCK below, run --preview until the look is right, then
# run with no arguments to batch the whole folder.

set -euo pipefail

# ============================ PARAMETER BLOCK ==============================
# Edit these to tune the look. No need to touch the filter string below.

INPUT_DIR="./input"        # folder of source .mp4 clips
OUTPUT_DIR="./output"      # folder for styled clips (created if missing)

STEP=75                    # LUMA posterize step. ~256/STEP = # of brightness levels
                           #   (75 -> ~3). Bigger = fewer/flatter. Range ~24 (subtle)
                           #   to 90 (extreme). Skin bands worst — judge on a face clip.
COLOR_STEP=64              # CHROMA posterize step — flattens the actual hues into
                           #   solid blocks (the big cel-shade lever). ~24 subtle,
                           #   64 chunky pop-art.
FLATTEN=20                 # bilateral flatten strength (spatial). Unlike a blur, this
                           #   keeps edges CRISP while filling regions with flat color —
                           #   this is what makes it graphic instead of soft/real.
                           #   0 = off, ~10 mild, ~20 strong, ~30 poster-paint.
FLATTEN_PASSES=2           # times to run the flatten. More = flatter blocks, harder
                           #   look. 1-3. (2 is the sweet spot; 3 starts eating detail.)
SATURATION=2.8             # color boost (1.0 = unchanged)
CONTRAST=1.4               # contrast boost (1.0 = unchanged)

EDGES=true                 # true = draw bold ink outlines; false = posterize only
LINE_THICKEN=2             # ink-line thickness (erosion passes). 0 = thin, 1 = bold,
                           #   2 = heavy comic ink, 3 = thick (can merge fine detail
                           #   like small text). THIS is the "harder lines" knob.
EDGE_OPACITY=1.0           # ink-line darkness. 1.0 = solid black, lower = softer.
EDGE_LOW=0.1               # edgedetect lower threshold (lower = more/finer lines)
EDGE_HIGH=0.4              # edgedetect upper threshold (higher = only strong edges)

PREVIEW_SECONDS=4          # length of the middle snippet in --preview mode

# Encoder settings (output is re-imported into Camtasia).
CRF=18                     # x264 quality: lower = better/larger (18 = visually lossless-ish)
PRESET=medium              # x264 speed/size tradeoff
# ===========================================================================


# --------------------------- filter construction ---------------------------
# The hard cel/comic look is built in three logical stages that share one
# flattened image (via split), so the ink lines trace the SAME clean edges as
# the flat color — that's what makes it read as one drawing:
#
#   FLATTEN : eq (saturation/contrast) + bilateral*N. Bilateral is edge-PRESERVING
#             — it fills regions with flat color while keeping boundaries sharp, so
#             the result is graphic, not blurry.
#   BASE    : the flattened image, luma+chroma quantized into posterize bands.
#   EDGES   : the flattened image -> edgedetect -> negate (black lines on white)
#             -> erosion*LINE_THICKEN (each pass fattens the black lines) -> multiply
#             onto BASE. Detecting on the FLATTENED image gives clean bold outlines
#             instead of noisy ones traced from photographic texture.

# eq + N bilateral passes. Shared by both branches.
flatten_chain() {
  local f i
  f=$(printf 'eq=saturation=%s:contrast=%s' "$SATURATION" "$CONTRAST")
  if [ "${FLATTEN%.*}" -gt 0 ] 2>/dev/null; then
    for ((i=0; i<FLATTEN_PASSES; i++)); do
      f="$f,$(printf 'bilateral=sigmaS=%s:sigmaR=0.1' "$FLATTEN")"
    done
  fi
  printf '%s' "$f"
}

# luma + chroma posterize.
posterize_chain() {
  printf 'lutyuv=y=(val/%s)*%s:u=(val/%s)*%s:v=(val/%s)*%s' \
    "$STEP" "$STEP" "$COLOR_STEP" "$COLOR_STEP" "$COLOR_STEP" "$COLOR_STEP"
}

# edgedetect -> negate -> thicken lines. Trailing erosions set outline weight.
edge_chain() {
  local f i
  f=$(printf 'edgedetect=low=%s:high=%s,negate' "$EDGE_LOW" "$EDGE_HIGH")
  for ((i=0; i<LINE_THICKEN; i++)); do f="$f,erosion"; done
  printf '%s,format=yuv420p' "$f"
}

# Build the ffmpeg video args (filter graph + stream maps) into a global array.
#
# NOTE on the edge blend: edgedetect+negate produces a grayscale map whose chroma
# is neutral (128). A plain blend=multiply would multiply the chroma planes too,
# dragging colors toward green. We multiply ONLY the luma plane (c0) and pass the
# base chroma straight through (c1/c2 opacity 0) so outlines darken without tint.
build_video_args() {
  VIDEO_ARGS=()
  if [ "$EDGES" = "true" ]; then
    VIDEO_ARGS+=(-filter_complex
      "[0:v]$(flatten_chain),split[flat1][flat2];\
[flat1]$(posterize_chain)[base];\
[flat2]$(edge_chain)[edges];\
[base][edges]blend=all_mode=multiply:c0_opacity=${EDGE_OPACITY}:c1_opacity=0:c2_opacity=0[out]"
      -map "[out]" -map "0:a?")
  else
    VIDEO_ARGS+=(-vf "$(flatten_chain),$(posterize_chain)" -map 0:v -map "0:a?")
  fi
}

# Encode one file. $1 = input, $2 = output, plus any extra ffmpeg input args ($3..)
encode() {
  local in="$1" out="$2"; shift 2
  build_video_args
  ffmpeg -hide_banner -y "$@" -i "$in" \
    "${VIDEO_ARGS[@]}" \
    -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
    -c:a copy -movflags +faststart \
    "$out"
}


# ------------------------------ arg parsing --------------------------------
PREVIEW=false
PREVIEW_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --preview) PREVIEW=true
               # optional non-flag argument = specific clip to preview
               if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then PREVIEW_FILE="$2"; shift; fi ;;
    -i)        INPUT_DIR="$2"; shift ;;
    -o)        OUTPUT_DIR="$2"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *)         echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v ffmpeg >/dev/null || { echo "ffmpeg not found on PATH" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe not found on PATH" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"

echo "Settings: luma_step=$STEP color_step=$COLOR_STEP flatten=${FLATTEN}x${FLATTEN_PASSES} sat=$SATURATION con=$CONTRAST edges=$EDGES thicken=$LINE_THICKEN opacity=$EDGE_OPACITY"


# ------------------------------ preview mode -------------------------------
if [ "$PREVIEW" = "true" ]; then
  if [ -z "$PREVIEW_FILE" ]; then
    # first .mp4 in INPUT_DIR (case-insensitive)
    PREVIEW_FILE=$(find "$INPUT_DIR" -maxdepth 1 -type f -iname '*.mp4' | sort | head -n1)
  fi
  [ -n "$PREVIEW_FILE" ] && [ -f "$PREVIEW_FILE" ] || {
    echo "No clip to preview. Put .mp4s in '$INPUT_DIR' or pass a file path." >&2; exit 1; }

  # seek to the middle: start = duration/2 - PREVIEW_SECONDS/2 (clamped to >= 0)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$PREVIEW_FILE")
  start=$(awk -v d="$dur" -v p="$PREVIEW_SECONDS" 'BEGIN{s=d/2-p/2; if(s<0)s=0; printf "%.2f", s}')

  base=$(basename "$PREVIEW_FILE"); base="${base%.*}"
  out="$OUTPUT_DIR/${base}_preview.mp4"
  echo "Preview: '$PREVIEW_FILE'  ->  '$out'  (${PREVIEW_SECONDS}s from ${start}s)"
  # -ss/-t before -i (in encode's extra args) for a fast, accurate middle snippet
  encode "$PREVIEW_FILE" "$out" -ss "$start" -t "$PREVIEW_SECONDS"
  echo "Done. Review '$out', tweak the parameter block, and re-run --preview."
  exit 0
fi


# ------------------------------- batch mode --------------------------------
shopt -s nullglob nocaseglob
clips=("$INPUT_DIR"/*.mp4)
shopt -u nocaseglob
[ ${#clips[@]} -gt 0 ] || { echo "No .mp4 files found in '$INPUT_DIR'." >&2; exit 1; }

echo "Batch: ${#clips[@]} clip(s)  '$INPUT_DIR' -> '$OUTPUT_DIR'"
n=0
for in in "${clips[@]}"; do
  n=$((n+1))
  base=$(basename "$in"); base="${base%.*}"
  out="$OUTPUT_DIR/${base}_comic.mp4"
  echo "[$n/${#clips[@]}] $in -> $out"
  encode "$in" "$out"
done
echo "Done. $n clip(s) written to '$OUTPUT_DIR'."
