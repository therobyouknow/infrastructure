#!/usr/bin/env bash
#
# hero-loop.sh — cut a short, silent, web-sized looping clip (and a poster
# frame) for a website hero from a YouTube video or a local file.
#
# What it makes, next to each other in the output folder:
#   <name>.mp4        H.264 High, yuv420p, no audio, faststart, 25 fps,
#                     scaled to the chosen width (default 1280 => 1280x720),
#                     optionally with a strip cropped off the top first (-C)
#   <name>-poster.webp  one frame (default: the first frame of the clip),
#                     same crop, same width unless -W says otherwise, WebP quality 75
#
# Usage:
#   ./hero-loop.sh -u 'https://youtu.be/XXXX' -s 00:01:12 -t 20 -o ./out -n hero-1280
#   ./hero-loop.sh -i source.mp4 -s 72 -t 18 -p 80 -w 1920 -n hero-1920
#   ./hero-loop.sh -i source.mp4 -s 80 -t 19 -C 6.67 -W 1920 -n hero-1280   # 1280x672 clip, 1920-wide poster
#   ./hero-loop.sh -h
#
# The source is never modified. A downloaded source is kept as
# <out>/source.<ext> so you can re-cut without downloading again.
# Needs yt-dlp (for -u), ffmpeg/ffprobe and cwebp (brew install yt-dlp ffmpeg webp).

set -euo pipefail

URL=""
INPUT=""
START="0"
DURATION="20"
POSTER_AT=""
WIDTH="1280"
POSTER_WIDTH=""
CROP_TOP="0"
CRF="27"
PRESET="slow"
OUT="."
NAME="hero-1280"
COOKIES=""
OVERWRITE=0

usage() {
  cat <<'USAGE'
Usage: hero-loop.sh (-u URL | -i FILE) [options]

  -u URL      YouTube (or other yt-dlp) URL to download; best mp4 video up to 1080p, no audio needed
  -i FILE     Local source video instead of -u
  -s START    Start of the clip, seconds or hh:mm:ss (default 0)
  -t SECONDS  Length of the clip (default 20; 15 to 25 loops best)
  -p AT       Poster frame time, seconds or hh:mm:ss (default: START)
  -w WIDTH    Output width in pixels, height follows the source ratio (default 1280)
  -W WIDTH    Poster width in pixels (default: same as -w)
  -C PERCENT  Crop this much off the top of the frame before scaling, e.g. 6.67 (default 0).
              Use it when the frame has headroom (ceiling, lights) above the subject; a
              shorter frame is also a smaller file. The output height stays an even number.
  -q CRF      x264 quality, lower = better/bigger (default 27; 26-28 for a hero)
  -P PRESET   x264 preset (default slow)
  -o DIR      Output folder (default .)
  -n NAME     Output base name (default hero-1280)
  -c BROWSER  Pass --cookies-from-browser BROWSER to yt-dlp (e.g. chrome) if a download needs a signed-in session
  -y          Overwrite existing outputs
  -h          This help

Loop tip: pick a start where the camera is steady and the subject is centred,
and a length that ends on similar framing to where it began; the join is far
less visible when the clip is short.
USAGE
}

while getopts ":u:i:s:t:p:w:W:C:q:P:o:n:c:yh" opt; do
  case "$opt" in
    u) URL="$OPTARG" ;;
    i) INPUT="$OPTARG" ;;
    s) START="$OPTARG" ;;
    t) DURATION="$OPTARG" ;;
    p) POSTER_AT="$OPTARG" ;;
    w) WIDTH="$OPTARG" ;;
    W) POSTER_WIDTH="$OPTARG" ;;
    C) CROP_TOP="$OPTARG" ;;
    q) CRF="$OPTARG" ;;
    P) PRESET="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    n) NAME="$OPTARG" ;;
    c) COOKIES="$OPTARG" ;;
    y) OVERWRITE=1 ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option -$OPTARG" >&2; usage; exit 2 ;;
    :) echo "Option -$OPTARG needs a value" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$URL" && -z "$INPUT" ]]; then
  echo "Give a source: -u URL or -i FILE" >&2; usage; exit 2
fi
for tool in ffmpeg ffprobe cwebp; do
  command -v "$tool" >/dev/null || { echo "$tool not found; brew install ffmpeg webp" >&2; exit 1; }
done
POSTER_AT="${POSTER_AT:-$START}"
POSTER_WIDTH="${POSTER_WIDTH:-$WIDTH}"
mkdir -p "$OUT"

if [[ -n "$URL" ]]; then
  command -v yt-dlp >/dev/null || { echo "yt-dlp not found; brew install yt-dlp" >&2; exit 1; }
  existing=$(ls "$OUT"/source.* 2>/dev/null | head -1 || true)
  if [[ -n "$existing" && $OVERWRITE -eq 0 ]]; then
    echo "Using existing download: $existing"
    INPUT="$existing"
  else
    cookie_opt=()
    [[ -n "$COOKIES" ]] && cookie_opt=(--cookies-from-browser "$COOKIES")
    yt-dlp "${cookie_opt[@]}" --no-playlist -f "bv*[height<=1080][ext=mp4]/bv*[height<=1080]/bv*" \
      -o "$OUT/source.%(ext)s" "$URL"
    INPUT=$(ls "$OUT"/source.* | head -1)
  fi
fi

[[ -f "$INPUT" ]] || { echo "Source not found: $INPUT" >&2; exit 1; }

MP4="$OUT/$NAME.mp4"
POSTER_PNG="$OUT/$NAME-poster.png"
POSTER="$OUT/$NAME-poster.webp"
if [[ $OVERWRITE -eq 0 ]]; then
  for f in "$MP4" "$POSTER"; do
    [[ -e "$f" ]] && { echo "Exists: $f (use -y to overwrite)" >&2; exit 1; }
  done
fi

echo "Source : $INPUT"
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate -show_entries format=duration -of default=nw=1 "$INPUT" | sed 's/^/         /'
echo "Clip   : start $START, ${DURATION}s, width $WIDTH, crop top ${CROP_TOP}%, crf $CRF, preset $PRESET"

# Crop first (a strip off the top, as a fraction of the source height; the
# crop filter rounds to whole pixels), then scale. Without -C it is a no-op.
CROP="crop=iw:ih*(1-${CROP_TOP}/100):0:ih*${CROP_TOP}/100,"
[[ "$CROP_TOP" == "0" ]] && CROP=""

# -ss before -i seeks fast; -an drops audio; scale keeps the ratio, height to an even number.
ffmpeg -y -loglevel error -stats -ss "$START" -t "$DURATION" -i "$INPUT" -an \
  -vf "${CROP}scale=${WIDTH}:-2,fps=25" \
  -c:v libx264 -profile:v high -crf "$CRF" -preset "$PRESET" -pix_fmt yuv420p \
  -movflags +faststart "$MP4"

ffmpeg -y -loglevel error -ss "$POSTER_AT" -i "$INPUT" -frames:v 1 -vf "${CROP}scale=${POSTER_WIDTH}:-2" "$POSTER_PNG"
cwebp -quiet -q 75 "$POSTER_PNG" -o "$POSTER"
rm -f "$POSTER_PNG"

echo
echo "Made:"
ls -la "$MP4" "$POSTER" | awk '{printf "  %8.0f KB  %s\n", $5/1024, $NF}'
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name,profile -show_entries format=duration -of default=nw=1 "$MP4" | sed 's/^/  /'
