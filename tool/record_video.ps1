# Records a docs video of the real Windows app while an integration test drives it.
#   powershell -File tool/record_video.ps1 -Flow record_block
#   powershell -File tool/record_video.ps1 -Flow reports
param([Parameter(Mandatory)][ValidateSet('record_block', 'reports')][string]$Flow)
$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot/.."
$out = "$root/docs/_static/videos"
$marks = Join-Path ([IO.Path]::GetTempPath()) "dbs_video_$Flow"
$raw = "$marks/raw.mkv"
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { $ffmpeg = "$env:LOCALAPPDATA/Microsoft/WinGet/Links/ffmpeg.exe" }
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'C:/ProgramData/flutter/bin/flutter.bat' }

Remove-Item $marks -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $marks, $out | Out-Null

function Wait-Mark($name, $test) {
    while (-not (Test-Path "$marks/$name")) {
        if ($test.HasExited) { throw "The test ended before '$name'. See $marks/test.log" }
        Start-Sleep -Milliseconds 100
    }
}

$test = Start-Process $flutter -PassThru -NoNewWindow -WorkingDirectory $root `
    -RedirectStandardOutput "$marks/test.log" -RedirectStandardError "$marks/test.err" `
    -ArgumentList "test integration_test/videos/${Flow}_test.dart -d windows --dart-define=VIDEO_ROOT=$root --dart-define=VIDEO_MARKS=$marks"
Wait-Mark ready $test

$psi = [Diagnostics.ProcessStartInfo]::new($ffmpeg,
    "-y -hide_banner -loglevel error -f gdigrab -framerate 30 -draw_mouse 0 -i `"title=DBS Annotator video`" -c:v libx264 -preset ultrafast -crf 10 `"$raw`"")
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$rec = [Diagnostics.Process]::Start($psi)
Wait-Mark done $test
$rec.StandardInput.Write('q')
$rec.WaitForExit()
$test.WaitForExit()

& $ffmpeg -y -hide_banner -loglevel error -i $raw -vf 'scale=1280:-2' -c:v libx264 -crf 28 `
    -pix_fmt yuv420p -movflags +faststart -an "$out/$Flow.mp4"
& $ffmpeg -y -hide_banner -loglevel error -ss 0.5 -i "$out/$Flow.mp4" -frames:v 1 "$out/$Flow.png"
Get-Item "$out/$Flow.mp4", "$out/$Flow.png" | Select-Object Name, Length
