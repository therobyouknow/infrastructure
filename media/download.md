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

### Cookies file straight from the browser, no extension

gallery-dl can read the browser's cookies once and write them out as a
cookies.txt. One-off cost: Full Disk Access for the terminal (above) and one
Keychain prompt for Chrome's cookie key. After that the file works anywhere,
including WSL2, where Windows Chrome's cookies can't be read directly.

```bash
gallery-dl --cookies-from-browser chrome/instagram.com   --cookies-export ~/ig-cookies.txt -s "https://www.instagram.com/p/DfPaTstI5AS/"
chmod 600 ~/ig-cookies.txt
grep -c sessionid ~/ig-cookies.txt    # 1 = good; 0 = not logged in, or wrong profile
```

`/instagram.com` limits the export to Instagram's cookies rather than every
site you are logged into, and `-s` simulates rather than downloads. For a
non-default Chrome profile use `"chrome/instagram.com:Profile 1"`. The file is
your login in plaintext: keep it outside any repo and treat it like a password.
It stays valid for months, until you log out of Instagram in that browser.
Revoke Full Disk Access again afterwards if you prefer; the file no longer
needs it.

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

## Saved posts (bookmarks) from a data export

`igsaved.py` takes Instagram's "Download your information" export, pulls out
every saved post and collection, and downloads the media into one folder per
author, with the collection name and author in each filename:

```
ig-saved/
  alice_art/
    alice_art_Events_20250309_C1a2B3c_01.jpg       # saved in "Events"
    alice_art_Events_20250309_C1a2B3c_02.mp4       # same post, 2nd carousel item
    alice_art_Events_20250309_C1a2B3c_02-out.mp4   # igpad output, with --pad
    alice_art_20240101_D4e5F6g_01.jpg              # saved, but in no collection
  bob.video/
    bob.video_Events+Food_20250310_H7i8J9k_01.mp4  # in two collections
  saved-posts.csv                                   # every bookmark + status
  .igsaved/                                         # progress; re-runs skip what's done
```

**1. Request the export.** Instagram → Settings → Accounts Center → Your
information and permissions → Download your information (the menus move; the
search box in Settings finds it). Choose "Some of your information" → *Saved*,
and on the next screen set **Date range: All time**. The default is *Last
year*, and it silently drops older bookmarks *and* every collection created
before that window — a Nov 2026 export with the default range came back with
1757 posts and one collection, the all-time one with 2215 posts and all 15.
Format can be JSON or HTML; both parse, JSON is the cleaner source. Instagram
emails a link a few hours later; the ZIP may arrive in several parts — pass
them all, the tool finds `your_instagram_activity/saved/saved_posts.*` and
`saved_collections.*` wherever they are.

Format notes, for when Instagram changes it again (`--list` showing 0 posts is
the symptom; `parse_exports` in the script is where to look):

- JSON before 2026: `saved_saved_media` / `saved_saved_collections` with
  `string_map_data`.
- JSON from at least Nov 2026: flat list of entries with `label_values`, the
  author under an "Owner" group, collections carrying their member posts under
  a "Media" group. A single collection is written as a bare object, not a list.
- HTML: nested tables with the same fields; parsed by matching the export's
  exact cell markup, so a restyle of the HTML would break it. Its dates are
  rendered in Meta's Pacific time but labelled "UTC"; the script derives the
  real offset from the page header, where the same instant appears both ways,
  and corrects every date (verified to the minute against a JSON export of the
  same account, Nov 2026).

**2. Get cookies.** Instagram serves almost nothing to a logged-out client, so
use a cookies file (see *Cookies* above). `--cookies-from-browser chrome` works
too but on macOS needs Full Disk Access.

**3. Look before downloading.**

```bash
./igsaved.py ~/Downloads/instagram-*.zip --list                   # collections and authors, with counts
./igsaved.py ~/Downloads/instagram-*.zip -o ~/ig-saved --dry-run  # the plan, nothing written
```

**4. Download in batches.** Bulk fetching against a logged-in account is
exactly what Instagram rate-limits, so keep runs small and let the tool sleep
between posts (default 4–10 s). Progress is saved after every post, so Ctrl-C
is safe and re-running continues where it stopped.

```bash
./igsaved.py ~/Downloads/instagram-*.zip -o ~/ig-saved -c ~/ig-cookies.txt -n 40
./igsaved.py ~/Downloads/instagram-*.zip -o ~/ig-saved -c ~/ig-cookies.txt --collection Events
```

**Just the recent ones.** Posts are processed most-recently-saved first, so a
limited run always starts with what you bookmarked last. `--since` narrows it
to a window, by the date *you saved* the post (the only date the export has;
the date in each filename is when the post was published):

```bash
./igsaved.py export.zip -o ~/ig-saved -c ~/ig-cookies.txt --since 3m                 # last three months
./igsaved.py export.zip -o ~/ig-saved -c ~/ig-cookies.txt --since 2026-10-01 --until 2026-11-01
./igsaved.py export.zip -o ~/ig-saved -c ~/ig-cookies.txt --collection Events --since 90d
```

`--list` prints a saved-per-month table to help pick the window. Note that a
post is only in a collection if you filed it there; recently saved posts that
you haven't filed yet are found by `--since` without `--collection`.
`--order oldest` or `--order author` changes the processing order.

Five failures in a row aborts the run — that is nearly always rate limiting or
an expired session, not five deleted posts. Wait an hour (or refresh cookies)
and re-run with `--retry-failed`. Genuinely deleted or private posts stay
listed as `failed` in `saved-posts.csv` with the reason.

**5. Pad reels for feed posting (optional).** `--pad` runs `igpad.sh` on every
author folder that received new videos, so a 9:16 reel becomes a 4:5
`<name>-out.mp4` beside the original. Originals are kept. It is off by default
because re-encoding hundreds of reels takes a while and you may only want a
few; the same thing later, by hand, is:

```bash
./igsaved.py ... --pad                       # or --pad --pad-fill blur
./igpad.sh -d ~/ig-saved/alice_art           # same result for one folder, afterwards
```

**How it downloads.** gallery-dl does the fetching because it handles image
posts, videos and carousels alike; yt-dlp's Instagram extractor is video-only.
If gallery-dl fails on a post, yt-dlp is tried as a fallback (`--no-fallback`
to skip that). Both tools use the cookies you pass.

**Without an export.** gallery-dl can also read saved posts straight from the
logged-in account: `gallery-dl --cookies FILE "https://www.instagram.com/USERNAME/saved/"`
(or `.../saved/COLLECTION-NAME/COLLECTION-ID/` for one collection, URL copied
from the browser). That gets you the files but not the per-author folders or
collection names in filenames, and it has to page through Instagram's API for
the list, which is the rate-limited part. The export route gets the list for
free.

Requires: `brew install gallery-dl yt-dlp ffmpeg`. Python 3.10+, standard
library only.

---

## See also

- `igpad.sh` — pads clips to 1080x1350 (feed) or 1080x1920 (reel) so Instagram
  doesn't crop them. `-c` checks without writing. Run `./igpad.sh --help`.
- `igsaved.py` — downloads all saved posts from a data export, per author, and
  can hand the videos to `igpad.sh`. Run `./igsaved.py --help`.
