# screentime

A background recorder for your own working day, and an AI analysis layer that
reads it back to you. Every five seconds it stores one screenshot per display
plus a line of metadata. An agent turns a day of that into a written report,
and keeps a ledger of the inefficiencies that keep coming back.

Everything stays on your machine. Nothing is uploaded, no account is needed,
there is no server component.

## Passwords are never recorded

This is the part to read before anything else.

**Layer one, before the shutter.** Every tick, the recorder reads the window
titles of all visible windows. If any of them matches the block list, the
screenshot for that display is not taken at all. There is no file to leak and
no file to delete, because the frame never existed. On multiple displays only
the affected display is skipped and the others are stored as usual.

The block list covers these by default:

| Category | Matched |
| --- | --- |
| Password managers | 1Password, Bitwarden, LastPass, Dashlane, KeePass, Proton Pass |
| System password stores | Apple Keychain, macOS Passwords, Windows Credential Manager |
| Browser password pages | `passwords.google.com`, any window titled Passwords or Password Manager |
| Second factor and recovery | Authenticator apps, Authentication code, Recovery Code, Seed Phrase, Secret Recovery |
| Key and secret files | `.env`, `id_rsa`, `id_ed25519`, `.pem`, `.p12`, `credentials.json`, `secrets.yaml/json/env/txt`, `.netrc`, `.pgpass` |
| Key material in a text window | any window whose title contains `BEGIN ... PRIVATE KEY` |
| One time setup tokens | any window titled `setup-token`, the short lived credential some CLI tools print during a first login |

You extend it by editing one line in the capture script. Both platform scripts
carry the same list.

**Layer two, during analysis.** A window title cannot catch everything. A
password typed into an unnamed dialog, a key pasted into a chat, a photographed
ID document, none of those announce themselves. So the analysis carries a
standing rule that is not optional. Any frame showing a plaintext password, a
password manager entry, a 2FA or recovery code, a private key, a seed phrase,
an API token, full card or banking credentials or an identity document is
deleted permanently on sight, before anything else happens with it. Not moved
to the trash, not copied first, and never quoted, described or summarised
anywhere. The day's report records only an anonymous count, for example
"3 frames deleted (sensitive content)".

The two layers are deliberately different in kind. The first is mechanical and
runs before capture. The second is a judgement and runs after. Neither replaces
the other.

## What the analysis produces

Run it through the agent skill in `skill/`. Three commands.

**`analyze [date]`** builds one day's report. It starts from the metadata log,
which answers every quantitative question for almost no cost. Which apps, for
how long, how often you switched, which pages you were on. Then it reads the
screenshots, all of them, and writes a timeline of what you actually worked on
plus a list of observed inefficiencies with the frame that proves each one.

**`optimize [focus]`** reads the ledger of recurring patterns and turns the
confirmed ones into concrete recommendations, ranked by the time each would
save per week. A pattern counts as confirmed at three sightings. Below that it
is noise, and a recommendation built on one observation is a guess.

**`status`** reports whether the recorder is running, today's frame count and
disk usage, and recent capture errors.

Typical findings from a day of real work: several terminal windows covering
each other so the same command gets retyped, a tool opened through three clicks
that has a keyboard shortcut, the same two values copied back and forth between
two apps, a file dialog navigated by hand every single time.

## Which models read what

The screenshots are read in two passes, and the split is what keeps it
affordable.

The **cheap model** describes every frame of the day. It works in blocks of at
most fifty files, in parallel, and its brief is to describe and to flag, not to
judge and not to delete. Above fifty files per block a model stops reading
everything and starts sampling, while still reporting success, so the block
size is a hard limit rather than a suggestion.

The **strong model** opens only what the cheap pass flagged. It makes every
judgement call, owns every delete decision, and validates the cheap model's
reported timeline against the real timestamps before believing a word of it.
A cheap model will happily invent detailed activity for hours that have no data
at all.

The consequence is that a full day gets read completely rather than sampled,
which is the only way a pattern that recurs four times looks different from a
one-off.

## Storage

Frames are stored at 1568 pixels on the long edge, which is the most a vision
model can use. Larger is wasted disk and wasted tokens. WebP at quality 35
lands at roughly 80 KB per frame, JPEG at quality 55 is the fallback when no
WebP encoder is installed.

Three things keep the volume down. An unchanged screen (same app, same window,
same page) is only photographed every sixth tick. No keyboard or mouse input
for ninety seconds means no capture at all. And image folders older than the
retention window are deleted automatically.

A stored frame is around 80 KB at the default width and quality. With a seven
day retention window, a single display and a full working day, expect **roughly
120 MB per day and a bit over 800 MB on disk at any time**. Every further
display adds the same again. The metadata log is well under a megabyte per day
and is not the driver.

Reports are text and are never pruned. They are what remains after the images
are gone.

## Requirements

macOS 12 or newer, or Windows 10 or newer. `python3` (macOS ships it). A C
compiler for the two small macOS helpers (Xcode command line tools). Optional
but recommended on macOS, `cwebp` from Homebrew for smaller frames.

## Install

macOS: [`mac/install-notes.md`](mac/install-notes.md), and read the permission
note below first. Windows: [`windows/install-notes.md`](windows/install-notes.md).

### The macOS permission note

macOS attaches screen recording permission to the identity of the program that
asks for it. A bare shell script launched by launchd is attributed to
`/bin/bash`, and the request is denied silently. Granting the permission to
`/bin/bash` would also be the wrong fix, because it hands that right to every
script that ever runs through it.

So the recorder ships as a small compiled wrapper inside an app bundle. The
bundle is what appears in System Settings, under the name Screentime, and the
permission belongs to it alone. Compile once, sign once, then grant. Signing
again invalidates the grant and you have to grant it again.

Windows needs no equivalent permission.

## Privacy scan

[`scripts/privacy-scan.sh`](scripts/privacy-scan.sh) greps the whole working
tree for things that should never be committed, meaning email addresses, home
directory paths and any personal marker you list in `.privacy-markers`. Copy
`.privacy-markers.example` to `.privacy-markers` (it is gitignored) and put
your own name, company names and project names in it. Run the scan before
every commit.

[`tests/test_privacy_scan.sh`](tests/test_privacy_scan.sh) verifies the scan
actually works, because a broken grep and a clean repository look exactly the
same from the outside.

## What this version does not have

Named honestly, so nothing here promises more than it does.

- No setup script and no setup questionnaire. Installation is six steps by
  hand, see the install notes. Interval, idle threshold, retention and frame
  width are constants at the top of the capture script and are edited there.
- No index across reports. Finding which day something happened on means
  reading the reports.
- No export to Obsidian or any other note system.
- No per site time tracking or distraction classification, and no memory of
  what you have told it is not a distraction.
- Windows records the frontmost window only, and has no browser URL. Window
  titles usually carry the page title, which is often enough, but it is less
  than the macOS branch sees.

## License

MIT, see [`LICENSE`](LICENSE).
