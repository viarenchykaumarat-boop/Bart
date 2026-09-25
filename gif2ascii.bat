@echo off
setlocal EnableExtensions
title GIF to ASCII
chcp 65001 >nul 2>&1

set "GIF_ASCII_SECONDS=12"

start "" "C:\36\assets\song.mp3"

set "GIF_ASCII_AUTO=C:\36\assets\animation.gif"

set "GIF_ASCII_SELF=%~f0"
set "GIF_ASCII_FILE="

if not "%~1"=="" (
  set "GIF_ASCII_FILE=%~f1"
) else if defined GIF_ASCII_AUTO (
  set "GIF_ASCII_FILE=%GIF_ASCII_AUTO%"
) else (
  echo Convert a GIF into a scaled ASCII animation in this window.
  echo.
  echo Drag a .gif onto this .bat file, OR drop one into this window
  echo so the path pastes, then press Enter.
  echo.
  echo While it plays, press Q to quit.
  echo.
  set /p "GIF_ASCII_FILE=GIF path: "
)

REM Strip accidental quotes pasted by a drag-and-drop.
if defined GIF_ASCII_FILE set GIF_ASCII_FILE=%GIF_ASCII_FILE:"=%

if not defined GIF_ASCII_FILE (
  echo No file was given.
  goto :hold
)

if not exist "%GIF_ASCII_FILE%" (
  echo File not found: %GIF_ASCII_FILE%
  goto :hold
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
  "$c=Get-Content -LiteralPath $env:GIF_ASCII_SELF; $n=0; for($i=0;$i -lt $c.Count;$i++){ if($c[$i] -eq ':::GIF2ASCII_PS'){ $n=$i+1; break } }; Invoke-Expression (($c[$n..($c.Count-1)] -join [char]10))"
if errorlevel 1 (
  echo.
  echo Could not play that GIF.
  goto :hold
)

goto :hold

:hold
echo.
pause
exit /b 0

goto :EOF
:::GIF2ASCII_PS
$ErrorActionPreference = 'Stop'
$gifPath = $env:GIF_ASCII_FILE.Trim().Trim('"')

$soundPath = $env:GIF_ASCII_SOUND.Trim().Trim('"')

$player = $null

if (-not [string]::IsNullOrWhiteSpace($soundPath) -and (Test-Path -LiteralPath $soundPath)) {
  try {
    $player = New-Object -ComObject WMPlayer.OCX
    $player.settings.autoStart = $false
    $player.settings.setMode("loop", $true)
    $player.URL = (Resolve-Path -LiteralPath $soundPath).Path
    $player.controls.play()
  }
  catch {
    $player = $null
  }
}

if ([string]::IsNullOrWhiteSpace($gifPath) -or -not (Test-Path -LiteralPath $gifPath)) {
  Write-Host "File not found: $gifPath"
  exit 1
}

if (-not ('GifAscii.Native' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace GifAscii {
  public static class Native {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out int mode);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, int mode);
  }
}
'@
}

$handle = [GifAscii.Native]::GetStdHandle(-11)
$mode = 0
if ([GifAscii.Native]::GetConsoleMode($handle, [ref]$mode)) {
  [void][GifAscii.Native]::SetConsoleMode($handle, $mode -bor 4)
}

Add-Type -AssemblyName System.Drawing

function Test-QuitKey {
  $quit = $false
  while ([Console]::KeyAvailable) {
    $key = [Console]::ReadKey($true)
    if ($key.Key -eq 'Q' -or $key.Key -eq 'Escape') { $quit = $true }
  }
  return $quit
}

$esc = [char]27
$ramp = ' .,:;irsXA253hMHGS#9B&@'
$img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $gifPath).Path)

try {
  $dimension = $null
  $frameCount = 1
  foreach ($guid in $img.FrameDimensionsList) {
    $candidate = New-Object System.Drawing.Imaging.FrameDimension $guid
    try {
      $count = $img.GetFrameCount($candidate)
      if ($count -ge 1) {
        $dimension = $candidate
        $frameCount = $count
        if ($count -gt 1) { break }
      }
    } catch { }
  }
  if (-not $dimension) {
    $dimension = [System.Drawing.Imaging.FrameDimension]::Time
  }

  $delays = New-Object int[] $frameCount
  for ($i = 0; $i -lt $frameCount; $i++) { $delays[$i] = 100 }
  try {
    $prop = $img.GetPropertyItem(0x5100)
    if ($prop -and $prop.Value) {
      for ($i = 0; $i -lt $frameCount; $i++) {
        if (($i * 4 + 3) -ge $prop.Value.Length) { break }
        $hundredths = [BitConverter]::ToInt32($prop.Value, $i * 4)
        if ($hundredths -le 0) { $hundredths = 10 }
        $delays[$i] = [Math]::Max(40, $hundredths * 10)
      }
    }
  } catch { }

  $maxW = [Math]::Max(20, [Console]::WindowWidth - 1)
  $maxH = [Math]::Max(8, [Console]::WindowHeight - 2)
  $charAspect = 0.48
  $scale = [Math]::Min($maxW / [double]$img.Width, $maxH / ([double]$img.Height * $charAspect))
  $cols = [Math]::Max(12, [int]($img.Width * $scale))
  $rows = [Math]::Max(6, [int]($img.Height * $scale * $charAspect))
  if ($cols -gt $maxW) { $cols = $maxW }
  if ($rows -gt $maxH) { $rows = $maxH }

  $scaled = New-Object System.Drawing.Bitmap $cols, $rows, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gfx = [System.Drawing.Graphics]::FromImage($scaled)
  $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
  $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
  $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

  [Console]::CursorVisible = $false
  [void](Test-QuitKey)
  $name = [IO.Path]::GetFileName($gifPath)

  $playSeconds = 0
  $rawSeconds = $env:GIF_ASCII_SECONDS
  if (-not [string]::IsNullOrWhiteSpace($rawSeconds)) {
    $parsed = 0.0
    if ([double]::TryParse($rawSeconds.Trim(), [ref]$parsed) -and $parsed -gt 0) {
      $playSeconds = $parsed
    }
  }
  $deadline = $null
  if ($playSeconds -gt 0) { $deadline = [datetime]::UtcNow.AddSeconds($playSeconds) }

  $hint = 'press Q to quit'
  if ($playSeconds -gt 0) { $hint = "plays ${playSeconds}s  $hint" }

  $running = $true
  while ($running) {
    for ($frame = 0; $frame -lt $frameCount -and $running; $frame++) {
      if (Test-QuitKey) { $running = $false; break }
      if ($deadline -and [datetime]::UtcNow -ge $deadline) { $running = $false; break }

      [void]$img.SelectActiveFrame($dimension, $frame)
      $gfx.Clear([System.Drawing.Color]::Black)
      $gfx.DrawImage($img, 0, 0, $cols, $rows)

      $sb = New-Object System.Text.StringBuilder (($cols + 24) * ($rows + 2))
      [void]$sb.Append("$esc[H")
      [void]$sb.Append("$esc[90m$name  ${cols}x${rows}  $hint$esc[0m$esc[K`r`n")

      for ($y = 0; $y -lt $rows; $y++) {
        for ($x = 0; $x -lt $cols; $x++) {
          $px = $scaled.GetPixel($x, $y)
          $gray = [int](($px.R * 299 + $px.G * 587 + $px.B * 114) / 1000)
          $idx = [Math]::Min($ramp.Length - 1, [int](($gray / 255.0) * ($ramp.Length - 1)))
          [void]$sb.Append("$esc[38;2;$($px.R);$($px.G);$($px.B)m")
          [void]$sb.Append($ramp[$idx])
        }
        [void]$sb.Append("$esc[0m$esc[K`r`n")
      }

      [Console]::Write($sb.ToString())
      Start-Sleep -Milliseconds $delays[$frame]
    }
  }
}
catch {
  Write-Host $_
  exit 1
}
finally {
  try { [Console]::CursorVisible = $true } catch { }
  try { [Console]::Write("$esc[0m") } catch { }
  if ($gfx) { $gfx.Dispose() }
  if ($scaled) { $scaled.Dispose() }
  if ($img) { $img.Dispose() }
}
