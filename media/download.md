# Downloading media with yt-dlp

Reference commands for `yt-dlp`. Install with `brew install yt-dlp ffmpeg` (macOS)
or `pipx install "yt-dlp[default,curl-cffi]"` (see *Impersonation* below for why
the pipx form is sometimes needed).

---

## Workflow: reel → feed post

The common case: download something from Instagram or YouTube, then post it to
the Instagram feed without it being cropped or showing up as a blank icon in
Finder. Three steps.

**1. Download with the codec flags.** H.264 so Finder and Adobe Bridge can
thumbnail it, without sacrificing resolution. Details under *Picking formats*.

```bash
yt-dlp -S "res,vcodec:h264,ext:mp4:m4a" --merge-output-format mp4 \
  --cookies-from-browser chrome -o "%(uploader_id)s-%(upload_date)s-%(id)s.%(ext)s" "<url>"
```

**2. Check whether it needs padding.** Feed posts cap at 4:5 (1080x1350), so a
reel at 9:16 (1080x1920) or a 2:3 clip (720x1080) gets cropped top and bottom
if posted as-is. `igpad.sh -c` probes each file and says so without writing
anything:

```bash
./igpad.sh -d ~/Downloads -c
```

| Input | Ratio | Feed post verdict |
|---|---|---|
| 1080x1920 (reel/story) | 9:16 | taller than 4:5 → pad left/right |
| 720x1080 | 2:3 | taller than 4:5 → pad left/right |
| 1080x1350 | 4:5 | fits, no bars needed |
| 1080x1080 | 1:1 | fits; igpad adds bars top/bottom only to fill 4:5 |
| 1920x1080 | 16:9 | fits; igpad adds bars top/bottom only to fill 4:5 |

Rule of thumb: anything **taller than 4:5** will be cropped, and that is the
case to care about. Wider clips are not cropped by Instagram, but padding them
to 4:5 gives a bigger tile in the feed.

The same check with `-m reel` tells you what happens for Reels/Stories at 9:16.

The check also reports codec and pixel format, so a `vp9` or `hevc` download
shows up here before you discover it won't thumbnail.

**3. Pad.** Only if step 2 said so, or if you want the codec normalised anyway:

```bash
./igpad.sh -d ~/Downloads            # black bars
./igpad.sh -d ~/Downloads -f blur    # blurred copy of the clip as the bars
```

Outputs go beside the originals as `<name>-out.mp4`. Originals are never
touched.

---

## Cookies

Anything behind a login — Instagram stories, private or age-gated content —
needs your browser session.

### Straight from the browser

```bash
# For Chrome
yt-dlp --cookies-from-browser chrome "https://youtube.com"

# For Firefox
yt-dlp --cookies-from-browser firefox "https://youtube.com"

# For Safari
yt-dlp --cookies-from-browser safari "https://youtube.com"
```

Non-default Chrome profile:

```bash
yt-dlp --cookies-from-browser "chrome:Profile 1" "<url>"
yt-dlp --cookies-from-browser "chrome:$HOME/Library/Application Support/Google/Chrome/Profile 1" "<url>"
```

### macOS: "could not find chrome cookies database"

Usually a permissions problem, not a missing file. Check with:

```bash
ls -la ~/Library/Application\ Support/Google/Chrome/
```

`Operation not permitted` means macOS privacy protection (TCC) is blocking the
terminal. Grant the *terminal app* (not yt-dlp) Full Disk Access:

**System Settings → Privacy & Security → Full Disk Access**, add Terminal /
iTerm2 / VS Code, then **quit that app entirely (⌘Q) and reopen it**.

There is no way to scope this to a single folder — Full Disk Access is
all-or-nothing. Revoke it again afterwards if that matters.

### Cookies file (no special permissions needed)

Export with a "Get cookies.txt LOCALLY" browser extension while logged in, then:

```bash
yt-dlp --cookies ~/Downloads/instagram.com_cookies.txt "<url>"
```

More robust than `--cookies-from-browser`: survives macOS permission changes and
Chrome's cookie encryption shifting about.

---

## Instagram

### Reels and posts

```bash
yt-dlp --cookies-from-browser chrome "https://www.instagram.com/reels/XXXXXXXXXXX/"
yt-dlp --cookies-from-browser chrome "https://www.instagram.com/p/XXXXXXXXXXX/"
```

### Stories

Stories always require a logged-in session, and you must actually be able to see
them in the browser (public account, or an account you follow).

```bash
# Every currently-live story from one account (24h window)
yt-dlp --cookies ~/Downloads/instagram.com_cookies.txt \
  "https://www.instagram.com/stories/USERNAME/"

# One specific story item
yt-dlp --cookies ~/Downloads/instagram.com_cookies.txt \
  "https://www.instagram.com/stories/USERNAME/1234567890123456789/"
```

Get the story ID by opening the story in a desktop browser and reading it off
the address bar.

Stories vanish after 24 hours, so there is no retrying later — grab them while
they are live. Highlights (below) are the permanent form.

### Highlights

```bash
yt-dlp --cookies ~/Downloads/instagram.com_cookies.txt \
  "https://www.instagram.com/stories/highlights/12345678901234567/"
```

The numeric highlight ID is **mandatory** here — `.../stories/highlights/` on its
own fails with "Input URL is missing a highlight ID".

### Useful extras

```bash
# Name files usefully instead of by bare ID
-o "%(uploader_id)s-%(upload_date)s-%(id)s.%(ext)s"

# Skip items already downloaded (good for repeat story grabs)
--download-archive ~/.yt-dlp-archive.txt

# See what's there without downloading
--flat-playlist -J
```

---

## Troubleshooting Instagram

### "You need to log in to access this content"

Work through these in order.

**1. Update first.** The Instagram extractor breaks often.

```bash
brew upgrade yt-dlp
yt-dlp --version
```

**2. Impersonation.** The Instagram extractor impersonates a real browser's TLS
fingerprint, which needs `curl_cffi`. Check whether yours can:

```bash
yt-dlp --list-impersonate-targets
```

Empty list = the feature is unavailable, and stories are the first thing to
fail. The Homebrew build does not always include it. Fix:

```bash
brew uninstall yt-dlp
brew install pipx && pipx ensurepath
pipx install "yt-dlp[default,curl-cffi]"
```

**3. Try the iOS API path.** The extractor defaults to Instagram's web app ID;
the mobile one sometimes succeeds where the web one doesn't:

```bash
yt-dlp --extractor-args "instagram:app_id=ios" --cookies <file> "<story url>"
```

**4. Try a nightly build.** Stories extraction was reported broken in
Sept–Oct 2026 (yt-dlp issues #17755, #17903) with a fix in PR #17885 still under
review, so a nightly may be ahead of stable:

```bash
pipx install --suffix=-nightly \
  "yt-dlp[default,curl-cffi] @ https://github.com/yt-dlp/yt-dlp/archive/refs/heads/master.tar.gz"
```

**5. Check the cookies are being seen.** Add `-v` and look for:

```
[debug] [Instagram] Found Instagram account cookies.
```

If that line is missing, the cookies aren't reaching the extractor — the problem
is the cookie source, not Instagram.

### Rate limiting

Bulk downloading against a logged-in account is something Instagram acts on.
Keep volumes modest and space requests out:

```bash
--sleep-requests 2 --min-sleep-interval 5 --max-sleep-interval 15
```

---

## Picking formats

No re-encoding happens — `-S` only chooses between streams the site already
offers, and `--merge-output-format` remuxes rather than transcodes.

```bash
# Default: best available (may be VP9/AV1, which macOS won't thumbnail)
yt-dlp "<url>"

# Prefer H.264 so Finder and Adobe Bridge can generate thumbnails,
# WITHOUT giving up resolution (res is sorted before vcodec)
yt-dlp -S "res,vcodec:h264,ext:mp4:m4a" --merge-output-format mp4 "<url>"
```

Order matters. Putting `vcodec:h264` *first* promotes codec above resolution,
which on YouTube silently caps you at 1080p because 1440p/2160p exist only as
VP9/AV1. Instagram serves H.264/AAC only, so for Instagram the flags are a no-op.

### Fixing files that won't thumbnail

```bash
# Check what you've got
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,codec_tag_string,pix_fmt -of csv=p=0 FILE.mp4
```

| Result | Fix |
|---|---|
| `h264,avc1,yuv420p` | Fine — it's a Finder cache issue: `qlmanage -r cache && killall Finder` |
| `hevc,hev1,...` | Lossless retag: `ffmpeg -i in.mp4 -c copy -tag:v hvc1 out.mp4` |
| `vp9` / `av01` | Re-encode to H.264 (see `igpad.sh`, which does this anyway) |
| `yuv420p10le` / `yuv444p` | Re-encode to 8-bit `yuv420p` |

---

## See also

- `igpad.sh` — pads clips to 1080x1350 (feed) or 1080x1920 (reel) so Instagram
  doesn't crop them. `-c` checks without writing. Run `./igpad.sh --help`.
