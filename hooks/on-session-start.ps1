<#
.SYNOPSIS
    SessionStart hook - plays JARVIS session.start sound when Claude Code opens.
#>
$root         = "C:\Users\tscr\tools\claude-herald"
$configPath   = Join-Path $root "config.json"
$notifyScript = Join-Path $root "engine\notify.ps1"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

# Play session.start sound directly (not via notify.ps1 event system)
if ($config.audio.enabled) {
    $packName   = $config.audio.active_pack
    $packDir    = Join-Path $root "sounds\$packName"
    $manifestP  = Join-Path $packDir "openpeon.json"
    $playScript = Join-Path $root "engine\play.ps1"

    if (Test-Path $manifestP) {
        $manifest  = Get-Content $manifestP -Raw | ConvertFrom-Json
        $catSounds = $manifest.categories.PSObject.Properties |
                     Where-Object { $_.Name -eq "session.start" } |
                     Select-Object -First 1

        if ($catSounds -and $catSounds.Value.sounds.Count -gt 0) {
            $soundFiles = $catSounds.Value.sounds
            $pick       = $soundFiles[(Get-Random -Maximum $soundFiles.Count)]
            $fileName   = Split-Path $pick.file -Leaf
            $filePath   = Join-Path $packDir "sounds\$fileName"

            if (Test-Path $filePath) {
                Start-Process powershell -WindowStyle Hidden -ArgumentList @(
                    "-NoProfile", "-NonInteractive",
                    "-File", "`"$playScript`"",
                    "-Path", "`"$filePath`"",
                    "-Volume", ([double]$config.audio.volume)
                )
            }
        }
    }
}

# Relay session_start to Orchestrator if running
if (Test-Path $configPath) {
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $orchPath = if ($cfg.orchestrator) { $cfg.orchestrator.path } else { "" }
    if ($orchPath -and (Test-Path $orchPath)) {
        $orchPid = (Get-Content (Join-Path $orchPath ".orch-pid") -Raw -ErrorAction SilentlyContinue).Trim()
        if ($orchPid -and (Get-Process -Id ([int]$orchPid) -ErrorAction SilentlyContinue)) {
            '{"event":"session_start","message":"","timestamp":"' + (Get-Date -f 'o') + '"}' |
                Add-Content (Join-Path $orchPath ".orch-events") -Encoding UTF8
        }
    }
}

# Pass through - do not block session