# Windows install notes

1. Copy `capture-loop.ps1` to `%USERPROFILE%\screentime\bin\capture-loop.ps1`.
2. Register it to start at logon (run in a normal PowerShell/cmd, no admin needed):

```
schtasks /Create /TN Screentime /SC ONLOGON /TR "powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File %USERPROFILE%\screentime\bin\capture-loop.ps1" /F
schtasks /Run /TN Screentime
```

3. Verify: within ~30 seconds, `%USERPROFILE%\screentime\days\<today>\` should contain `.jpg` frames and a `log.jsonl` whose lines have a non-empty `"app"`.

Control:
- Pause: `schtasks /End /TN Screentime`
- Resume: `schtasks /Run /TN Screentime`
- Remove: `schtasks /Delete /TN Screentime /F`

Notes:
- No permission prompts on Windows — screen capture just works for desktop apps.
- Black frames = DRM-protected content or an RDP session; that's expected.
- The blocklist here checks the foreground window title only. macOS also checks
  the browser URL and scans every visible window on every screen, so a password
  manager opened as a browser tab is caught there but not here. The analysis
  layer deletes such frames as a second net.
- Browser URLs aren't captured (window titles include the page title, which
  covers most analysis). UI Automation-based URL capture is a possible upgrade.
- If `ffmpeg` is installed and on PATH, swapping the JPEG save for WebP
  (`ffmpeg -i in.png -vf scale=1568:-2 -quality 35 out.webp`) roughly halves
  the file size.
