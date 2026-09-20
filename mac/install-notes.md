# Installing on macOS

There is no setup script in this version. Six steps by hand, about five minutes.

Below, `KIT` means the directory you cloned this repository into.

## 1. Build the window scanner

```bash
cc -framework CoreGraphics -framework CoreFoundation \
   -o "$KIT/mac/windowscan" "$KIT/mac/windowscan.c"
```

The capture loop calls this every tick to read the titles of all visible
windows. It is what makes the block list work across several displays. The loop
is fail-closed: if the scanner is missing or says nothing, no screenshot is
stored at all.

## 2. Build the app bundle

Screen recording permission attaches to the code identity of the program that
asks for it. A shell script started by launchd is attributed to `/bin/bash`, so
the grant never matches and capture fails silently. Granting `/bin/bash` would
be worse, because it hands that right to every script that ever runs through it.
Hence a compiled wrapper inside a bundle that carries the permission alone.

```bash
mkdir -p ~/Applications/Screentime.app/Contents/MacOS
cp "$KIT/mac/Info.plist" ~/Applications/Screentime.app/Contents/
cc -DSCRIPT_PATH="\"$KIT/mac/capture-loop.sh\"" \
   -o ~/Applications/Screentime.app/Contents/MacOS/screentime \
   "$KIT/mac/wrapper.c"
codesign -s - --force --identifier com.screentime ~/Applications/Screentime.app
```

Compile and sign once, then grant the permissions. Signing again invalidates
every grant you have already given and you start over at step 4.

## 3. Install the launchd job

```bash
sed "s|__HOME__|$HOME|g" "$KIT/mac/com.screentime.plist" \
  > ~/Library/LaunchAgents/com.screentime.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.screentime.plist
```

The log path has to sit on the internal disk. launchd cannot open a log file on
an external volume.

## 4. Grant the permissions

Open System Settings, Privacy and Security. Under **Screen and System Audio
Recording** and under **Accessibility**, enable **Screentime**. That name is
what you will see in the list, not `bash` and not `python3`, which is the whole
point of the bundle.

You may have to restart the job once after granting:

```bash
launchctl kickstart -k gui/$(id -u)/com.screentime
```

## 5. Check it runs

```bash
launchctl print gui/$(id -u)/com.screentime | head -5
ls ~/screentime/days/$(date +%F) | head
cat ~/screentime/daemon.log
```

Frames appear within a few seconds of activity. Nothing appears while you are
idle for more than ninety seconds, and nothing appears while a blocked window
is in front. Both are by design.

## 6. Install the analysis skill

Copy `skill/screentime/` into your agent's skills directory. For Claude Code
that is `~/.claude/skills/screentime/`.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.screentime.plist
rm ~/Library/LaunchAgents/com.screentime.plist
rm -rf ~/Applications/Screentime.app
rm -rf ~/screentime          # deletes your recordings and reports
```

Then remove Screentime from the two privacy lists in System Settings.

## Changing the settings

Interval, idle threshold, retention window, frame width and the block list are
constants at the top of `mac/capture-loop.sh`. Edit them there, then restart:

```bash
launchctl kickstart -k gui/$(id -u)/com.screentime
```
