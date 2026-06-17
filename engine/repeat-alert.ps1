<#
.SYNOPSIS
    Persistent repeat alert for claude-herald.
    Plays input.required sound every N seconds until the user responds.
    Stopped by the UserPromptSubmit hook deleting the sentinel file.
#>
param(
    [string]$Event          = "input",
    [int]$IntervalSeconds   = 10
)

$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$sentinelFile = Join-Path $root ".herald-alert"
$notifyScript = Join-Path $root "engine\notify.ps1"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

# Write our PID so on-submit can kill us
$PID | Set-Content $sentinelFile -Force

# Short messages for repeat pings - don't repeat the full line
$repeatMessages = @(
    "Still waiting for your response.",
    "Your input is needed.",
    "Standing by for you.",
    "Awaiting your reply."
)

$tick = 0
while (Test-Path $sentinelFile) {
    Start-Sleep -Seconds $IntervalSeconds
    # Re-check sentinel after sleep - user may have responded
    if (-not (Test-Path $sentinelFile)) { break }

    $msg = $repeatMessages[$tick % $repeatMessages.Count]
    $tick++

    # Play input.required sound from active pack
    if ($config.audio.enabled) {
        $packName  = $config.audio.active_pack
        $packDir   = Join-Path $root "sounds\$packName"
        $manifestP = Join-Path $packDir "openpeon.json"
        $playScript = Join-Path $root "engine\play.ps1"

        if (Test-Path $manifestP) {
            $manifest  = Get-Content $manifestP -Raw | ConvertFrom-Json
            $catSounds = $manifest.categories.PSObject.Properties |
                         Where-Object { $_.Name -eq "input.required" } |
                         Select-Object -First 1

            if ($catSounds) {
                $soundFiles = $catSounds.Value.sounds
                $pick       = $soundFiles[(Get-Random -Maximum $soundFiles.Count)]
                $fileName   = Split-Path $pick.file -Leaf
                $filePath   = Join-Path $packDir "sounds\$fileName"

                if (Test-Path $filePath) {
                    # Run play.ps1 inline (we ARE the background process)
                    & $playScript -Path $filePath -Volume ([double]$config.audio.volume)
                }
            }
        }
    }

    # Terminal nudge (brief - no full banner spam)
    if ($config.notify.terminal) {
        Write-Host "  [!] claude  $msg" -ForegroundColor Yellow
    }
}