---
name: screentime
description: Analyze the screentime capture archive — build daily activity notes, track recurring workflow inefficiencies, and suggest optimizations. Use for "/screentime analyze [date]", "/screentime optimize [focus]", "/screentime status", or any question about what the user was doing on a past day / how to improve their workflow based on observed behavior.
---

# Screentime analysis

## Data layout

Paths below assume the default `BASE` of `~/screentime`. If the capture script
was pointed somewhere else, read that path instead.

- `~/screentime/days/YYYY-MM-DD/log.jsonl` — one line per 5s tick:
  `{t, epoch, app, window, url, img}`. `img: true` means at least one screenshot
  of that tick was stored, **not** that `HH-MM-SS.webp` itself exists. A blocked
  screen 1 (see `blocked` below) leaves `img: true` with no `HH-MM-SS.webp` and
  only `HH-MM-SS-2.webp` beside it. **With more than one display attached there
  is one file per screen:** `HH-MM-SS.webp` plus `HH-MM-SS-2.webp`, `-3` and so
  on. Never assume `img: true` means exactly one file, or a full pass silently
  skips half the work surface. Match `HH-MM-SS*` when collecting a tick's frames.
- `blocked` is present only on ticks where the secret blocklist stopped a
  capture, and missing whenever nothing was blocked. `"all"` means no image was
  taken at all; otherwise it holds the skipped screen numbers (`"2"`, `"1 3"`),
  and the remaining screens were stored as usual. **A blocked tick is the
  blocklist working, not a broken daemon and not a lost frame to hunt for.** The
  frame was never taken, so there is nothing to recover and nothing to delete.
- `~/screentime/days/YYYY-MM-DD/*.webp|*.jpg` — ~1568px-wide screenshots, pruned
  after the retention window set in the capture script.
- `~/screentime/notes/YYYY-MM-DD.md` — analysis output, kept forever. This is the
  durable record once the images are gone.
- `~/screentime/observations.md` — rolling ledger of recurring inefficiencies with
  occurrence counts.

## Cost discipline (important)

Metadata first, vision second. The JSONL log answers every quantitative question
(what apps, how long, how often switching, which URLs) for near-zero tokens. No
screenshot improves those numbers, so aggregate the log with a `python3` script
via the shell, never by reading raw JSONL into context.

What vision adds is what metadata cannot: **patterns across the day** (a
behaviour that recurs four times looks like a one-off in a lucky-dip sample) and
**privacy coverage** (a secret with no tell-tale window title is invisible in
metadata). So every frame gets read, but cheaply. A cheap model describes them
all and you only open what it flags. See `analyze` step 2.

## Privacy safety net (non-negotiable)

Applies to every screenshot you open, under every command. If a frame shows a
password or other clearly confidential information — a revealed plaintext
password or password-manager entry, 2FA/recovery codes, private keys or seed
phrases, API keys/tokens, full card or banking credentials, an ID document, or
comparable secrets — **delete that image immediately and permanently** before
doing anything else with it: `rm -f <file>`, never to the trash, never a backup
copy. Never quote, describe, paraphrase, or store the sensitive content
anywhere, not in notes, not in `observations.md`, not in your reply. Leave
`log.jsonl` untouched; its metadata line simply points at a frame that no longer
exists. In the day's note record only an anonymous tally, for example "3 frames
deleted (sensitive content)".

**Active sweep (mandatory on every `analyze`):** before anything else, grep the
day's metadata for risky window titles and URLs (`env`, `secret`, `token`,
`key`, `password`, `credential`, `vault`, `1password`, `keychain`, `.pem`) and
open the matching frames first. They are the likeliest to show secrets.

## `analyze [date]` (default: yesterday if it has data, else today)

1. **Aggregate the log.** Collapse ticks into activity blocks (consecutive same
   app+window+url), compute per-app total time, block durations, context-switch
   rate per hour, top URLs and windows, and churn bursts (more than 6 app
   switches in 2 minutes).

   **Terminal work carries its project in the window title.** Many terminal
   setups put the session or project name in the title. Where they do, treat
   that project as the block's theme rather than the app name. Without this, a
   large share of the archive collapses into one undifferentiated terminal block
   and every theme switch inside the terminal disappears. Where the title is
   empty or generic, report that share as unattributed instead of folding it
   into the nearest theme. Inheriting a theme from a neighbouring block sounds
   reasonable and recovers almost nothing, so do not.

   Also count **window switches inside one app**, not just app switches. The two
   are of comparable size, and counting only app switches misses about half the
   movement.

2. **Full pass with a cheap model.** Dispatch parallel cheap-model subagents
   across **every** `img:true` frame of the day. **Count files, not ticks.** With
   several displays attached one tick writes one file per screen, so a range
   that looks like 50 ticks can hand one agent 150 images. Size each range by `ls` output, not
   by tick count. Give each agent one contiguous time range of **at most 50
   files** and cover the whole day block by block. Above 50 the model invents its
   own sampling strategy and reports it as success instead of stopping. Brief it
   to describe every frame and flag anything privacy-sensitive, but **not** to
   delete and **not** to judge. A cheap model's failure mode is under-detecting
   secrets, so delete rights stay with you.

3. **Read what the pass flagged, and validate it.** Open the privacy-flagged
   frames yourself and apply the safety net above; the delete decision is yours.
   Cross-check each agent's reported timeline against the real `log.jsonl`
   timestamps before trusting a word of it. A cheap model will fabricate detailed
   activity for hours that have zero ticks, for example across a sleep gap.
   Descriptions are leads; the metadata is ground truth.

4. **Look specifically for inefficiency evidence.** Open menus and right-click
   menus where a hotkey exists, manual file-dialog navigation, repeated
   copy-paste between the same two apps, hand-scrolling long documents instead of
   searching, dated or suboptimal tooling, undismissed notification piles,
   redoing something automatable, manual status-polling loops, and windows of the
   same app covering each other so the same work gets repeated.

5. **Write `~/screentime/notes/YYYY-MM-DD.md`.** A short timeline (activity blocks
   with times), what was worked on, tool inventory, and an "Inefficiencies
   observed" list with concrete evidence (frame filenames). Also note *positive*
   patterns worth keeping.

6. **Update `~/screentime/observations.md`.** For each inefficiency, if a matching
   entry exists increment its count and update `last:`; otherwise add one:

   `- [count: 3, last: 2026-01-08] Opens X via launcher → browser → typing URL; a pinned tab or launcher hotkey would be ~5s faster each time. (Seen: 2026-01-06/14-22-10.webp, ...)`

## `optimize [focus]`

1. Read `observations.md` and the last ~7 days of notes.
2. Entries with count >= 3 are confirmed patterns. Turn each into a specific
   recommendation: the exact hotkey, the replacement tool (verify it is current
   via web search if unsure), or an automation you can build on the spot (shell
   script, launcher command, browser extension, scheduled agent).
3. Rank by estimated time saved per week. Present the top 3 to 5 and offer to
   implement the automatable ones.
4. If `focus` is given (for example "browser", "email"), filter to that area.

## `status`

Report whether the capture daemon is running, today's frame count and disk
usage, and any recent errors.

```bash
launchctl print gui/$(id -u)/com.screentime     # macOS
```

Ticks carrying `blocked` were stopped on purpose by the secret blocklist. Count
those out before reading a missing frame or an `"img": false` as a fault.

Two logs, do not confuse them. `~/screentime/daemon.log` holds the capture errors
worth reading (osascript, screencapture, encoder). `~/Library/Logs/screentime.log`
is launchd's stdout and stderr.

If `BASE` points at an external or network volume, check it is mounted before
calling a zero frame count a failure. Capture pauses by design when the
directory is missing and resumes when it comes back, so a gap in the days is not
by itself a broken daemon.
