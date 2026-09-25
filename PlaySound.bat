@echo off
powershell.exe -NoProfile -WindowStyle Hidden -Command "$p = New-Object System.Media.SoundPlayer -ArgumentList '%~dp0song.wav'; $p.PlaySync()"
