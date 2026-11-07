#!/usr/bin/env bash
#
# ig-pad.sh — pad videos so Instagram stops cropping them.
#
# Instagram's tallest feed ratio is 4:5, so anything taller (e.g. 720x1080,
# which is 2:3) gets centre-cropped top and bottom. Padding LEFT and RIGHT to
# 4:5 fixes that. Reels/Stories are 9:16, which is taller than 2:3, so there
# the padding goes TOP and BOTTOM instead. This script does whichever is
# needed — it never crops, it only adds bars.
#
# Usage:
#   ./igpad.sh                           # show help
#   ./igpad.sh -d .                      # feed (1080x1350), black bars, current folder
#   ./igpad.sh -d . -m reel              # reel/story (1080x1920)
#   ./igpad.sh -d . -f blur              # blurred copy of the video as the bars
#   ./igpad.sh -d ~/Videos -m reel -f blur
#
# Originals are never touched. Output is <name>-out.mp4 alongside each input.

set -euo pipefail

MODE="feed"
FILL="black"
DIR="."
SUFFIX="-out"
CRF=18
PRESET="medium"
OVERWRITE=0

usage() {
  cat <<'EOF'
igpad.sh — pad videos so Instagram stops cropping them.

Instagram's tallest feed ratio is 4:5, so a taller clip (e.g. 720x1080, which
is 2:3) gets centre-cropped top and bottom. This pads LEFT and RIGHT to reach
4:5 instead. Reels/Stories are 9:16, taller than 2:3, so there the padding
goes TOP and BOTTOM. Nothing is ever cropped — bars are only added.

Usage: igpad.sh -d DIR [options]
       igpad.sh -h | --help

Options:
  -d DIR     Folder to process (default: current folder, i.e. -d .)
  -m MODE    feed  -> 1080x1350 (4:5, Instagram feed)   [default]
             reel  -> 1080x1920 (9:16, Reels/Stories)
  -f FILL    black -> solid black bars                  [default]
             blur  -> blurred, zoomed copy of the video as the bars
  -s SUFFIX  Output filename suffix (default: -out)
  -q CRF     x264 quality, lower = better/bigger (default: 18)
  -p PRESET  x264 preset (default: medium)
  -y         Overwrite existing output files
  -h, --help Show this help

Inputs:  .mp4 .MP4 .m4v .M4V .mov .MOV in DIR (not recursive).
Outputs: <name><SUFFIX>.mp4 beside each input, H.264 / yuv420p / faststart.
         Files already ending in SUFFIX are skipped, so re-running is safe.

Examples:
  ./igpad.sh -d ~/Downloads
  ./igpad.sh -d ~/Downloads -m reel -f blur
  ./igpad.sh -d . -q 20 -p slow -y

Requires: ffmpeg  (brew install ffmpeg)
EOF
}

# No arguments at all, or a help request anywhere in them -> show help and stop.
if [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

# getopts handles single-dash options only; fold --help into -h first.
ARGS=()
for a in "$@"; do
  case "$a" in
    --help) ARGS+=("-h") ;;
    --*) echo "Error: unknown option '$a' (this script takes single-dash options)" >&2
         echo "Try: igpad.sh --help" >&2
         exit 1 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]}"

while getopts ":d:m:f:s:q:p:yh" opt; do
  case "$opt" in
    d) DIR="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    f) FILL="$OPTARG" ;;
    s) SUFFIX="$OPTARG" ;;
    q) CRF="$OPTARG" ;;
    p) PRESET="$OPTARG" ;;
    y) OVERWRITE=1 ;;
    h) usage; exit 0 ;;
    :) echo "Error: -$OPTARG needs a value." >&2; exit 1 ;;
    \?) echo "Error: unknown option -$OPTARG" >&2; usage >&2; exit 1 ;;
  esac
done

command -v ffmpeg >/dev/null 2>&1 || {
  echo "Error: ffmpeg not found. Install it with:  brew install ffmpeg" >&2
  exit 1
}

[ -d "$DIR" ] || { echo "Error: no such folder: $DIR" >&2; exit 1; }

case "$MODE" in
  feed) W=1080; H=1350 ;;
  reel|story|reels) W=1080; H=1920 ;;
  *) echo "Error: -m must be 'feed' or 'reel' (got '$MODE')" >&2; exit 1 ;;
esac

case "$FILL" in
  black|blur) : ;;
  *) echo "Error: -f must be 'black' or 'blur' (got '$FILL')" >&2; exit 1 ;;
esac

# Collect .mp4 files (case-insensitive extension), skipping ones we made earlier.
shopt -s nullglob
FILES=()
for f in "$DIR"/*.mp4 "$DIR"/*.MP4 "$DIR"/*.M4V "$DIR"/*.m4v "$DIR"/*.mov "$DIR"/*.MOV; do
  [ -f "$f" ] || continue
  base="${f##*/}"
  stem="${base%.*}"
  case "$stem" in
    *"$SUFFIX") continue ;;   # already an output of this script
  esac
  FILES+=("$f")
done
shopt -u nullglob

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No video files found in: $DIR"
  exit 0
fi

echo "Target: ${W}x${H} ($MODE), fill: $FILL"
echo "Files:  ${#FILES[@]}"
echo

ok=0
skipped=0
failed=0

for in_file in "${FILES[@]}"; do
  dir="${in_file%/*}"
  base="${in_file##*/}"
  stem="${base%.*}"
  out_file="${dir}/${stem}${SUFFIX}.mp4"

  if [ -e "$out_file" ] && [ "$OVERWRITE" -eq 0 ]; then
    echo "skip   $base  (output already exists — use -y to overwrite)"
    skipped=$((skipped + 1))
    continue
  fi

  echo "-----> $base"

  if [ "$FILL" = "blur" ]; then
    ffmpeg -hide_banner -loglevel error -stats -y -i "$in_file" -filter_complex \
      "[0:v]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},gblur=sigma=20,setsar=1[bg];\
       [0:v]scale=${W}:${H}:force_original_aspect_ratio=decrease,setsar=1[fg];\
       [bg][fg]overlay=(W-w)/2:(H-h)/2" \
      -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
      -c:a copy -movflags +faststart "$out_file" \
      && ok=$((ok + 1)) || { failed=$((failed + 1)); rm -f "$out_file"; echo "       FAILED"; }
  else
    ffmpeg -hide_banner -loglevel error -stats -y -i "$in_file" -vf \
      "scale=${W}:${H}:force_original_aspect_ratio=decrease,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1" \
      -c:v libx264 -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
      -c:a copy -movflags +faststart "$out_file" \
      && ok=$((ok + 1)) || { failed=$((failed + 1)); rm -f "$out_file"; echo "       FAILED"; }
  fi
done

echo
echo "Done. $ok converted, $skipped skipped, $failed failed."
