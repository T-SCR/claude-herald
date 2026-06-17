<#
.SYNOPSIS
    Claude Code Stop hook - terminal banner + toast when Claude finishes a turn.
#>

$root          = Split-Path $PSScriptRoot -Parent
$configPath    = Join-Path $root "config.json"
$linesPath     = Join-Path $root "voice\lines.json"
$notifyScript  = Join-Path $root "engine\notify.ps1"
$pushScript    = Join-Path $root "engine\push.ps1"

if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled)       { exit 0 }
if (-not $config.hooks.on_stop) { exit 0 }

$lines = Get-Content $linesPath -Raw | ConvertFrom-Json

# Read hook payload from stdin
$payload = $null
try {
    $raw = $input | Out-String
    if ($raw.Trim()) { $payload = $raw | ConvertFrom-Json }
} catch { }

# Classify stop reason from last assistant message
$stopReason  = "done"
$lastMessage = ""

try {
    if ($payload -and $payload.transcript_path -and (Test-Path $payload.transcript_path)) {
        $transcript = Get-Content $payload.transcript_path -Raw | ConvertFrom-Json
        $messages   = $transcript.messages
        for ($i = $messages.Count - 1; $i -ge 0; $i--) {
            if ($messages[$i].role -eq "assistant") {
                $lastMessage = ($messages[$i].content |
                    Where-Object { $_.type -eq "text" } | Select-Object -Last 1).text
                break
            }
        }
    }
} catch { }

if ($lastMessage -match '\?\s*$') {
    $stopReason = "question"
} elseif ($lastMessage -match '(?i)(permission|allow|approve|authorize|confirm|deny|block)') {
    $stopReason = "permission"
} elseif ($lastMessage -match '(?i)(need|require|waiting|please|input|respond|clarif)') {
    $stopReason = "input"
} else {
    $stopReason = "done"
}

# Pick voice line from pool (used as toast/terminal body)
$lineKey = switch ($stopReason) {
    "done"       { "task_complete" }
    "question"   { "question" }
    "permission" { "permission_needed" }
    "input"      { "needs_input" }
    default      { "task_complete" }
}
$pool    = $lines.stop.$lineKey
$message = $pool[(Get-Random -Maximum $pool.Count)]

# Notify - terminal banner + async toast
& $notifyScript -Event $stopReason -Message $message

# Mobile push - only when you actually need to come back
if ($stopReason -in @("permission", "input", "question")) {
    $priority = if ($stopReason -eq "permission") { "high" } else { "default" }
    $label    = switch ($stopReason) {
        "permission" { "Claude - Authorization Required" }
        "question"   { "Claude - Question" }
        default      { "Claude - Needs Input" }
    }
    & $pushScript -Title $label -Body $message -Priority $priority
} elseif ($config.mobile.push_on_complete) {
    & $pushScript -Title "Claude - Done" -Body $message -Priority "low"
}