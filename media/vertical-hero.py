#!/usr/bin/env python3
"""
vertical-hero.py: turn a vertical (9:16) social-media clip into a widescreen,
silent, looping website hero.

The vertical clip plays inside a wide frame. At every scene change the old
scene holds its last frame and fades out slowly while the new scene fades in
quickly at a new position across the frame, so for a moment two clips share
the screen and the eye travels across it as the montage runs. The rest of
the frame is a flat colour (black by default) or a blurred, darkened copy of
the same footage. Everything that decides the look lives in an "edit
decision list", a small JSON file, so the result can be tuned by editing
numbers and re-rendering rather than by re-cutting in an editor.

Usage
  vertical-hero.py --detect clip.mp4 > edl.json       # write a starter EDL with the scene cuts
  vertical-hero.py edl.json                           # render what the EDL says
  vertical-hero.py edl.json --preview                 # quick low-quality render to check timing

EDL keys (all optional except "source"; defaults shown)
  source          "clip.mp4"           the vertical clip
  output          "hero-vertical"      base name; writes <output>.mp4 and <output>-poster.webp
  width, height   1920, 1008           frame size (40:21 matches the LIGC hero box; 1920x1080 for plain 16:9)
  fps             25
  cuts            [1.4, 2.57, ...]     scene-change times in seconds (from --detect; edit freely)
  start, end      0, <clip length>     trim the source
  clip_height     0.66                 vertical clip height as a fraction of the frame height
  fade_in         0.1                  seconds for a new scene to fade in at its new position
  fade_out        0.7                  seconds for the old scene to fade out (it holds its last frame
                                       while the new one already plays, so the two overlap)
  gutter          0.06                 fraction of the frame width kept clear at the left and right edges
  pattern         "pingpong"           how the clip moves: "pingpong" (left to right and back),
                                       "alternate" (left, right, left ...), "sweep" (left to right, then jump back),
                                       or "positions" (use the list below)
  positions       [0, 0.5, 1]          only for pattern "positions": 0 = left gutter, 1 = right gutter, cycled per scene
  background      "#000000"            a colour, or "blur" (blurred footage)
  blur            60                   blur radius for the blurred background
  background_dim  0.45                 0 = untouched blurred background, 1 = black
  poster_at       <middle of a scene>  time for the poster frame
  crf             27                   x264 quality, lower = better / bigger (26-30 for a hero)

Needs ffmpeg, ffprobe and cwebp (brew install ffmpeg webp).
"""

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys


def run(cmd, capture=False):
    if capture:
        return subprocess.run(cmd, check=True, capture_output=True, text=True)
    subprocess.run(cmd, check=True)


def probe(path):
    out = run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
               '-show_entries', 'stream=width,height,r_frame_rate:format=duration',
               '-of', 'json', path], capture=True).stdout
    info = json.loads(out)
    s = info['streams'][0]
    return int(s['width']), int(s['height']), float(info['format']['duration'])


def detect_cuts(path, threshold=8.0):
    """Scene-change times from ffmpeg's scdet filter."""
    res = subprocess.run(['ffmpeg', '-v', 'info', '-i', path, '-vf', f'scdet=t={threshold}',
                          '-an', '-f', 'null', '-'], capture_output=True, text=True)
    times = [float(t) for t in re.findall(r'lavfi\.scd\.time: ([0-9.]+)', res.stderr)]
    return sorted(set(round(t, 3) for t in times))


def starter_edl(path):
    w, h, dur = probe(path)
    return {
        'source': path,
        'output': 'hero-vertical',
        'width': 1920, 'height': 1008, 'fps': 25,
        'start': 0, 'end': round(dur, 3),
        'cuts': detect_cuts(path),
        'clip_height': 0.66, 'fade_in': 0.1, 'fade_out': 0.7, 'gutter': 0.06,
        'pattern': 'pingpong', 'positions': [0, 0.5, 1],
        'background': '#000000', 'blur': 60, 'background_dim': 0.45,
        'crf': 27,
    }


def even(n):
    n = int(round(n))
    return n if n % 2 == 0 else n - 1


def positions_for(n, pattern, listed):
    """A 0..1 horizontal position for each of n scenes."""
    if pattern == 'alternate':
        return [i % 2 for i in range(n)]
    if pattern == 'sweep':
        return [i / max(n - 1, 1) for i in range(n)]
    if pattern == 'positions':
        return [listed[i % len(listed)] for i in range(n)]
    # pingpong: across in the first half, back in the second, so the loop joins
    half = max(math.ceil(n / 2), 1)
    out = []
    for i in range(n):
        if i < half:
            out.append(i / max(half - 1, 1))
        else:
            back = n - half
            out.append(1 - (i - half + 1) / max(back, 1))
    return out


def build(edl, preview=False):
    src = edl['source']
    sw, sh, sdur = probe(src)
    W, H = int(edl.get('width', 1920)), int(edl.get('height', 1008))
    fps = int(edl.get('fps', 25))
    start = float(edl.get('start', 0))
    end = float(edl.get('end', sdur))
    length = end - start
    # "fade" from older EDLs sets both.
    fade_in = float(edl.get('fade_in', edl.get('fade', 0.1)))
    fade_out = float(edl.get('fade_out', edl.get('fade', 0.7)))
    gutter = float(edl.get('gutter', 0.06))
    clip_h = even(H * float(edl.get('clip_height', 0.66)))
    clip_w = even(clip_h * sw / sh)
    cuts = [c for c in edl.get('cuts', []) if start < c < end]
    bounds = [start] + cuts + [end]
    n = len(bounds) - 1
    pos = positions_for(n, edl.get('pattern', 'pingpong'), edl.get('positions', [0, 0.5, 1]))
    left = int(W * gutter)
    right = W - clip_w - left
    y = (H - clip_h) // 2
    bg = str(edl.get('background', '#000000'))
    dim = float(edl.get('background_dim', 0.45))
    blur = float(edl.get('blur', 60))
    crf = int(edl.get('crf', 27))
    out_base = edl.get('output', 'hero-vertical')

    # The source is split once into the background and one stream per scene.
    # Each scene is trimmed, moved to its place on the timeline (setpts), and
    # laid over the background in turn. The old scene keeps playing past the
    # cut on its held last frame (tpad clone) while it fades out, so it
    # overlaps the next scene, which fades in fast at its own position.
    parts = [f'[0:v]split={n + 1}[bgsrc]' + ''.join(f'[src{i}]' for i in range(n))]
    if bg == 'blur':
        parts.append(f'[bgsrc]trim=start={start}:end={end},setpts=PTS-STARTPTS,fps={fps},'
                     f'scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},'
                     f'gblur=sigma={blur},colorlevels=rimax={1 - dim}:gimax={1 - dim}:bimax={1 - dim}[bg]')
    else:
        parts.append(f'[bgsrc]nullsink;color=c={bg}:s={W}x{H}:r={fps}:d={length}[bg]')
    chain = '[bg]'
    for i in range(n):
        a, b = bounds[i], bounds[i + 1]
        seg = b - a
        fi = min(fade_in, seg / 2)
        last = (i == n - 1)
        # The last scene fades out inside the clip so the loop joins cleanly.
        hold = 0 if last else fade_out
        fo_start = (seg - fade_out) if last else seg
        x = int(left + (right - left) * pos[i])
        t0 = a - start
        parts.append(
            f'[src{i}]trim=start={a}:end={b},setpts=PTS-STARTPTS,fps={fps},'
            f'tpad=stop_mode=clone:stop_duration={hold},'
            f'scale={clip_w}:{clip_h},format=yuva420p,'
            f'fade=t=in:st=0:d={fi}:alpha=1,fade=t=out:st={max(fo_start, 0)}:d={fade_out}:alpha=1,'
            f'setpts=PTS+{t0}/TB[c{i}]')
        parts.append(f'{chain}[c{i}]overlay=x={x}:y={y}:eof_action=pass:format=auto[o{i}]')
        chain = f'[o{i}]'
    parts.append(f'{chain}trim=duration={length},format=yuv420p[v]')
    graph = ';'.join(parts)

    mp4 = f'{out_base}.mp4'
    cmd = ['ffmpeg', '-y', '-v', 'error', '-stats', '-i', src, '-filter_complex', graph, '-map', '[v]',
           '-an', '-c:v', 'libx264', '-profile:v', 'high', '-pix_fmt', 'yuv420p',
           '-preset', 'ultrafast' if preview else 'slow', '-crf', str(34 if preview else crf),
           '-movflags', '+faststart', '-r', str(fps), mp4]
    print(f'{n} scenes, clip {clip_w}x{clip_h} in {W}x{H}, fade in {fade_in}s / out {fade_out}s, '
          f'positions {[round(p, 2) for p in pos]}')
    run(cmd)
    size = os.path.getsize(mp4)
    print(f'wrote {mp4} ({size / 1024 / 1024:.1f} MB)')

    # Poster: a frame from the middle of the second scene (or poster_at), same frame.
    poster_at = edl.get('poster_at')
    if poster_at is None:
        k = min(1, n - 1)
        poster_at = (bounds[k] + bounds[k + 1]) / 2 - start
    png = f'{out_base}-poster.png'
    run(['ffmpeg', '-y', '-v', 'error', '-ss', str(poster_at), '-i', mp4, '-frames:v', '1', png])
    if shutil.which('cwebp'):
        run(['cwebp', '-quiet', '-q', '75', png, '-o', f'{out_base}-poster.webp'])
        os.remove(png)
        print(f'wrote {out_base}-poster.webp (frame at {poster_at:.2f}s)')
    else:
        print(f'wrote {png} (cwebp not found, no webp)')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('edl', nargs='?', help='EDL JSON file to render')
    ap.add_argument('--detect', metavar='CLIP', help='print a starter EDL for CLIP (scene cuts detected)')
    ap.add_argument('--threshold', type=float, default=8.0, help='scene-change sensitivity for --detect (lower = more cuts)')
    ap.add_argument('--preview', action='store_true', help='fast low-quality render')
    args = ap.parse_args()
    if args.detect:
        edl = starter_edl(args.detect)
        if args.threshold != 8.0:
            edl['cuts'] = detect_cuts(args.detect, args.threshold)
        json.dump(edl, sys.stdout, indent=2)
        print()
        return
    if not args.edl:
        ap.error('give an EDL file to render, or --detect CLIP')
    with open(args.edl) as fh:
        edl = json.load(fh)
    os.chdir(os.path.dirname(os.path.abspath(args.edl)))
    build(edl, preview=args.preview)


if __name__ == '__main__':
    main()
