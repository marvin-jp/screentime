#!/bin/bash
# screentime capture loop (macOS). Run via launchd through the Screentime.app
# wrapper — permissions attach to the app bundle, see the README.
set -u

BASE="$HOME/screentime"
# Window titles across all screens. Resolved next to this script so the repo
# can be cloned anywhere.
SCANNER="$(cd "$(dirname "$0")" && pwd)/windowscan"
INTERVAL=5
IDLE_SKIP_SECS=90       # skip capture if no keyboard/mouse input for this long
RETAIN_DAYS=7           # prune image folders older than this (notes never pruned)
WIDTH=1568              # AI vision max useful long edge — bigger is wasted
WEBP_QUALITY=35         # ~40-60KB/frame, verified legible
JPEG_QUALITY=55         # fallback when no webp encoder is available

# launchd doesn't inherit your shell PATH — find an encoder the hard way.
# cwebp is preferred. ffmpeg is only usable when libwebp is compiled in, and
# many builds are not, so the sips JPEG fallback below stays.
CWEBP=""
for c in "$(command -v cwebp 2>/dev/null)" /opt/homebrew/bin/cwebp /usr/local/bin/cwebp; do
  [ -n "$c" ] && [ -x "$c" ] && CWEBP="$c" && break
done
FFMPEG=""
for c in "$(command -v ffmpeg 2>/dev/null)" /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -hide_banner -encoders 2>/dev/null | grep -q libwebp \
    && FFMPEG="$c" && break
done

last_prune_day=""

get_meta() {
  # Prints: app <TAB> window_title. Only System Events here — browser
  # dictionaries are referenced in get_url so a missing browser can't
  # break compilation of this script.
  osascript <<'EOS' 2>>"$BASE/daemon.log"
tell application "System Events"
  set p to first application process whose frontmost is true
  set appName to name of p
  set winTitle to ""
  try
    set winTitle to name of front window of p
  end try
end tell
return appName & tab & winTitle
EOS
}

encode_frame() {
  # $1 = source PNG, $2 = target path without extension. Prints the file written.
  # Only ever shrink, never enlarge. A portrait screen is narrower than WIDTH,
  # and upscaling costs about 20 percent more bytes for not one pixel of extra
  # information. Measuring the source width costs 31 ms against 206 ms for the
  # encode itself, so the check pays for itself immediately.
  src_w=$(sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ {print $2}')
  target_w="$WIDTH"
  case "${src_w:-}" in
    ''|*[!0-9]*) ;;
    *) [ "$src_w" -lt "$WIDTH" ] && target_w="$src_w" ;;
  esac

  if [ -n "$CWEBP" ]; then
    "$CWEBP" -quiet -q "$WEBP_QUALITY" -resize "$target_w" 0 \
      "$1" -o "$2.webp" 2>>"$BASE/daemon.log"
    printf '%s' "$2.webp"
  elif [ -n "$FFMPEG" ]; then
    "$FFMPEG" -y -loglevel error -i "$1" \
      -vf "scale=$target_w:-2" -quality "$WEBP_QUALITY" "$2.webp" 2>>"$BASE/daemon.log"
    printf '%s' "$2.webp"
  else
    sips -s format jpeg -s formatOptions "$JPEG_QUALITY" \
      --resampleWidth "$target_w" "$1" --out "$2.jpg" >/dev/null 2>&1
    printf '%s' "$2.jpg"
  fi
}

get_url() {
  # $1 = frontmost app name. Separate per-browser scripts: AppleScript
  # resolves an app's dictionary at COMPILE time, so mentioning an
  # uninstalled browser is a syntax error that kills the whole script.
  case "$1" in
    "Google Chrome"|"Brave Browser"|"Arc"|"Microsoft Edge"|"Vivaldi")
      osascript -e "tell application \"$1\" to get URL of active tab of front window" 2>/dev/null ;;
    "Safari")
      osascript -e 'tell application "Safari" to get URL of front document' 2>/dev/null ;;
  esac
}

while true; do
  sleep "$INTERVAL"

  # BASE may live on an external disk — unmounted means skip the tick, not
  # spray mkdir/screencapture failures into the log until it comes back.
  [ -d "$BASE" ] || continue

  idle=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
  if [ "${idle:-0}" -ge "$IDLE_SKIP_SECS" ]; then continue; fi

  day=$(date +%F)
  dir="$BASE/days/$day"
  mkdir -p "$dir"
  ts=$(date +%H-%M-%S)
  epoch=$(date +%s)

  meta=$(get_meta)
  app=$(printf '%s' "$meta" | cut -f1)
  win=$(printf '%s' "$meta" | cut -f2)
  url=$(get_url "$app")

  # Blocklist: a window that deliberately writes a secret onto the screen is
  # logged as a metadata tick only, never as an image. A single command that
  # prints a long-lived token into a terminal can leave a credential on screen
  # for minutes. A deleted frame is the repair; a frame never taken is the fix.
  #
  # File names of real secret carriers are part of the pattern too: a window
  # titled .env or id_rsa is a secret on screen by its name alone, and it
  # almost never fires on anything else. Generic words like token, secret or
  # password stay out on purpose. They block a large number of harmless
  # windows, a chat whose title merely mentions the word being the usual
  # case, and a blocklist that cries wolf is one you switch off.
  #
  # Honest reach: this only catches what a window title or a URL reveals. A
  # secret inside a harmlessly titled window is invisible here and is caught by
  # the analysis layer instead. The window scan below widens it to every
  # visible window on every screen, but this check stays because only it knows
  # the URL — a password manager in a browser tab has a harmless window title.
  #
  # The gap stays visible in the log, because the tick is written with
  # "img": false. $blocked says which screens this tick did not photograph:
  # empty means none, "all" means no image at all, otherwise screen numbers.
  BLOCK_PATTERN='setup-token|Authentication code|1Password|Bitwarden|LastPass|Dashlane|KeePass|Proton Pass|Keychain|Passwords|Password Manager|Authenticator|Recovery Code|Seed Phrase|Secret Recovery|passwords\.google\.com|\.env|id_rsa|id_ed25519|\.pem|\.p12|credentials\.json|secrets?\.(ya?ml|json|env|txt)|\.netrc|\.pgpass|BEGIN [A-Z ]*PRIVATE KEY'
  blocked=""
  if printf '%s\n%s' "$win" "$url" | grep -qiE "$BLOCK_PATTERN"; then
    blocked="all"
  fi

  # Dedupe: unchanged app+window+url → metadata every tick, image every 6th.
  state="$app|$win|$url"
  saved=0
  if [ -z "$blocked" ] && { [ "$state" != "${last_state:-}" ] || [ $(( ${tick:-0} % 6 )) -eq 0 ]; }; then
    # Window scan: one line "<screen><TAB><title>" per visible window, plus one
    # line with an empty title for every screen without a titled window. That
    # yields both the numbers of the screens currently showing a secret and the
    # number of screens the scanner sees at all.
    # Fail-closed: if the program is missing, crashes, or says nothing, no
    # image is stored. A broken scanner costs recording, not confidentiality,
    # and shows up the same day.
    scan=$("$SCANNER" 2>>"$BASE/daemon.log") || scan=""
    hits=$(printf '%s\n' "$scan" | grep -iE "$BLOCK_PATTERN" | cut -f1 | sort -u | tr '\n' ' ')
    # Screen 0 does not count here: it is not a display. Counting it would let
    # a window pushed half off-screen skew the numbers and block every tick.
    displays=$(printf '%s\n' "$scan" | cut -f1 | grep -v '^0$' | sort -u | grep -c .)
    blocked="${hits% }"
    if [ -z "$scan" ]; then
      blocked="all"
      printf '%s window scan produced no output, tick blocked\n' "$(date +%FT%T)" >>"$BASE/daemon.log"
    fi
    # A hit on screen 0 sits on no display. It is then unknown which frame
    # shows it, so the whole tick is dropped.
    case " $hits " in *" 0 "*) blocked="all" ;; esac
    # NOTE: never a dot-prefixed temp name — screencapture refuses hidden
    # paths with an error identical to a permissions denial.
    # screencapture records EXACTLY ONE screen per file name handed to it. A
    # single name yields the main screen only, even without -m. Hand it more
    # names than there are screens and the surplus is silently ignored (exit
    # 0, no stderr, no empty file), so you get one file per screen. Hence a
    # fixed upper bound and collecting whatever appeared. The names are single
    # digits so the glob order below matches the display order. The first
    # screen keeps the plain HH-MM-SS name and every further one gets -2, -3,
    # so single-monitor setups stay bit-identical.
    tmpdir="$BASE/tmp-capture"
    rm -rf "$tmpdir"
    mkdir -p "$tmpdir"
    if [ "$blocked" != "all" ] && screencapture -x -t png \
         "$tmpdir/s1.png" "$tmpdir/s2.png" "$tmpdir/s3.png" \
         "$tmpdir/s4.png" "$tmpdir/s5.png" "$tmpdir/s6.png" \
         2>>"$BASE/daemon.log"; then
      # Fail-closed: if the frame count does not match the number of screens
      # seen, the screen-to-file mapping is no longer trustworthy, and a
      # shifted mapping would block the wrong screen and leave the secret
      # standing. Count first, encode second: in case of doubt nothing is
      # written, instead of something having to be deleted afterwards.
      pngs=0
      for src in "$tmpdir"/*.png; do [ -s "$src" ] && pngs=$(( pngs + 1 )); done
      if [ "$pngs" -ne "$displays" ]; then
        blocked="all"
        printf '%s window scan saw %s screens, screencapture returned %s frames, tick blocked\n' \
          "$(date +%FT%T)" "$displays" "$pngs" >>"$BASE/daemon.log"
      else
        n=0
        for src in "$tmpdir"/*.png; do
          [ -s "$src" ] || continue
          n=$(( n + 1 ))
          # The counter keeps running; only the encoding is skipped. Otherwise
          # screen 3 would suddenly be called -2 as soon as screen 2 is
          # blocked, and no file name would say which screen it came from.
          case " $hits " in *" $n "*) continue ;; esac
          if [ "$n" -eq 1 ]; then base="$dir/$ts"; else base="$dir/$ts-$n"; fi
          out=$(encode_frame "$src" "$base")
          [ -s "$out" ] && saved=1
        done
      fi
    fi
    rm -rf "$tmpdir"
  fi
  last_state="$state"
  tick=$(( ${tick:-0} + 1 ))

  APP="$app" WIN="$win" URL="$url" TS="$ts" EPOCH="$epoch" IMG="$saved" \
  BLOCKED="$blocked" \
  python3 - >> "$dir/log.jsonl" <<'EOF'
import json, os
row = {
  "t": os.environ["TS"], "epoch": int(os.environ["EPOCH"]),
  "app": os.environ["APP"], "window": os.environ["WIN"],
  "url": os.environ["URL"], "img": os.environ["IMG"] == "1",
}
# Only present when something was actually blocked, so every reader sees
# unchanged lines otherwise. "all" means no image, else the screen numbers.
if os.environ["BLOCKED"]:
    row["blocked"] = os.environ["BLOCKED"]
print(json.dumps(row))
EOF

  if [ "$day" != "$last_prune_day" ]; then
    find "$BASE/days" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETAIN_DAYS" \
      -exec rm -rf {} + 2>/dev/null
    last_prune_day="$day"
  fi
done
