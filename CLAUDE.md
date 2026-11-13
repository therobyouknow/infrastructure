# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this repo is

`infrastructure-tips` — Rob's personal collection of runbooks, playbooks and
small toolkits. It is **documentation and scripts, not a deployable app**. There
is no build, no test suite and no package manifest. Most files are either
Markdown runbooks or standalone shell scripts.

Layout:

| Path | Contents |
|---|---|
| `drupal/` | Drupal CMS 2 / Canvas playbooks, theming notes, helper PHP |
| `provision-site/toolkit/` | Shell toolkit for provisioning and deploying sites |
| `containerisation/` | Planning notes and roadmap |
| `local/runbooks/` | Fix-it notes for specific machine problems, dated |
| `media/` | Video prep for publishing — see below |
| `ide/`, `php/`, `databases/`, `setups/`, `wsl2-docker-ce/` | Environment setup notes |

## Target environments

Two, and scripts must work on both:

- **Primary dev:** Ubuntu 24.04 on WSL2 (Windows 11), DDEV for Drupal work. Bash 5.x.
- **Secondary:** a work Mac, zsh shell, Homebrew for tooling. **Bash 3.2** — macOS
  ships that and nothing newer.

Consequence: no Bash 4+ syntax in shell scripts. No `mapfile`, no associative
arrays, no `${var,,}`. `shopt -s nullglob` and `arr+=(x)` are fine.

## Conventions

**Shell scripts**

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- Support `-h` and `--help`, and print help when run with no arguments.
- `getopts` for options (single-dash); fold `--help` to `-h` before the loop.
- Never overwrite the user's input files. Write new files alongside, with a
  suffix, and skip existing outputs unless an explicit `-y` is passed.
- Check for required external tools with `command -v` and fail with an install
  hint rather than a stack trace.
- Quote paths — filenames with spaces are normal here.
- Clean up partial output if a long-running command fails midway.

**Markdown runbooks**

- Written as command cookbooks: short prose, runnable fenced code blocks.
- Say *why* a step is needed, not just what to type — these are read months later.
- Date-stamp anything describing a transient upstream bug, and name the issue or
  PR so it can be rechecked.
- Runbooks in `local/runbooks/` are named `YYYY-MM-DD-short-description.md`.

**Never commit** cookies files, `.env` files, keys, dumps or site credentials.
Reference them by path in examples instead.

## media/

Video prep for Instagram publishing.

- `igpad.sh` — pads clips so Instagram doesn't crop them. Feed posts cap at 4:5,
  so a 2:3 clip (e.g. 720x1080) gets centre-cropped top and bottom; padding goes
  **left and right** to reach 1080x1350. Reels/Stories are 9:16, taller than 2:3,
  so there the padding goes **top and bottom** to reach 1080x1920. It never
  crops. Outputs H.264 / yuv420p / faststart, which also makes the results
  thumbnail correctly in macOS Finder and Adobe Bridge.
- `igsaved.py` — downloads every saved post (bookmark) from an Instagram data
  export into one folder per author, collection name in the filename. Uses
  gallery-dl (images + videos), yt-dlp as fallback, and `--pad` hands new
  videos to `igpad.sh`. Python 3.10+ stdlib only, because it has to parse JSON
  and keep a resume state, which Bash 3.2 makes painful. Progress lives in
  `OUT/.igsaved/`; re-runs are idempotent.
- `hero-loop.sh` — loop/hero video generation.
- `download.md` — yt-dlp cookbook: cookies, Instagram reels/stories/highlights,
  format selection, and fixing files that won't thumbnail.

Testing video scripts without real footage:

```bash
ffmpeg -f lavfi -i testsrc=size=720x1080:rate=25:duration=2 \
       -c:v libx264 -pix_fmt yuv420p test.mp4

# verify geometry of the result
ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
        -of csv=p=0 test-out.mp4
```

Always `bash -n script.sh` before considering a shell change done, and prefer
proving a change with a generated clip over reasoning about the filtergraph.

## Working style

Rob is a solepreneur web developer with a deep Drupal background, and prefers
FOSS tooling and avoiding proprietary lock-in. He is methodical and will check
the reasoning, so explain trade-offs rather than asserting a choice, flag where
an approach has a real downside, and verify claims by running something rather
than asserting them.
