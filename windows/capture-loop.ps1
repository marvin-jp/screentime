# screentime capture loop (Windows). Register as a hidden logon task —
# see install-notes.md. Requires Windows PowerShell 5+ (built in).
$ErrorActionPreference = 'SilentlyContinue'

$Base         = "$env:USERPROFILE\screentime"
$Interval     = 5
$IdleSkipSecs = 90
$RetainDays   = 7
$Width        = 1568   # AI vision max useful long edge
$JpegQuality  = 50

# Blocklist: a window that deliberately writes a secret onto the screen is
# logged as a metadata tick only, never as an image. Windows sees less than
# macOS here — no browser URL and only the foreground window — so a password
# manager reached through a browser tab can slip past the title check. The
# analysis layer is the second net for that.
$BlockPattern = 'setup-token|Authentication code|1Password|Bitwarden|LastPass|Dashlane|KeePass|Proton Pass|Credential Manager|Passwords|Password Manager|Authenticator|Recovery Code|Seed Phrase|Secret Recovery|\.env|id_rsa|id_ed25519|\.pem|\.p12|credentials\.json|secrets?\.(ya?ml|json|env|txt)|\.netrc|BEGIN [A-Z ]*PRIVATE KEY'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class SW {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
}
"@

$jpegCodec  = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$encParams  = New-Object System.Drawing.Imaging.EncoderParameters(1)
$encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)

$lastState = ''; $tick = 0; $lastPruneDay = ''

while ($true) {
  Start-Sleep -Seconds $Interval

  # idle skip
  $lii = New-Object SW+LASTINPUTINFO
  $lii.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lii)
  [void][SW]::GetLastInputInfo([ref]$lii)
  $idleSecs = ([Environment]::TickCount - $lii.dwTime) / 1000
  if ($idleSecs -ge $IdleSkipSecs) { continue }

  $day = Get-Date -Format 'yyyy-MM-dd'
  $dir = Join-Path $Base "days\$day"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $ts    = Get-Date -Format 'HH-mm-ss'
  $epoch = [int][double]::Parse((Get-Date -UFormat %s))

  # frontmost app + window title (browser URLs not captured on Windows —
  # window titles carry the page title, which is usually enough)
  $h = [SW]::GetForegroundWindow()
  $sb = New-Object System.Text.StringBuilder 512
  [void][SW]::GetWindowText($h, $sb, 512)
  $win = $sb.ToString()
  $procId = 0; [void][SW]::GetWindowThreadProcessId($h, [ref]$procId)
  $app = (Get-Process -Id $procId).ProcessName

  $blocked = ''
  if ($win -match $BlockPattern) { $blocked = 'all' }

  $state = "$app|$win"
  $saved = $false
  if ($blocked -eq '' -and ($state -ne $lastState -or ($tick % 6) -eq 0)) {
    # All screens, one file per screen. The first keeps the plain HH-mm-ss
    # name and every further one gets -2, -3, so single-monitor setups stay
    # bit-identical to earlier versions.
    $n = 0
    foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
      $n++
      $bounds = $screen.Bounds
      $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
      $g.Dispose()

      $scale = $Width / $bmp.Width
      if ($scale -lt 1) {
        $small = New-Object System.Drawing.Bitmap($bmp, $Width, [int]($bmp.Height * $scale))
        $bmp.Dispose(); $bmp = $small
      }
      if ($n -eq 1) { $out = Join-Path $dir "$ts.jpg" } else { $out = Join-Path $dir "$ts-$n.jpg" }
      $bmp.Save($out, $jpegCodec, $encParams)
      $bmp.Dispose()
      if ((Get-Item $out).Length -gt 0) { $saved = $true }
    }
  }
  $lastState = $state; $tick++

  $row = @{ t = $ts; epoch = $epoch; app = $app; window = $win; url = ''; img = $saved }
  if ($blocked -ne '') { $row['blocked'] = $blocked }
  $row | ConvertTo-Json -Compress | Add-Content -Path (Join-Path $dir 'log.jsonl')

  if ($day -ne $lastPruneDay) {
    Get-ChildItem -Directory (Join-Path $Base 'days') |
      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetainDays) } |
      Remove-Item -Recurse -Force
    $lastPruneDay = $day
  }
}
