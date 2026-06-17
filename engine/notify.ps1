<#
.SYNOPSIS
    Core notification engine for claude-herald.
    Prints a styled terminal banner (instant) and fires a toast async (non-blocking).
.PARAMETER Event
    done | question | permission | input | tool
.PARAMETER Message
    The notification body line.
.PARAMETER Detail
    Optional context — filename, command preview, etc.
#>
param(
    [Parameter(Mandatory)][string]$Event,
    [string]$Message = "",
    [string]$Detail  = ""
)

$configPath = Join-Path $PSScriptRoot "..\config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

# ── Terminal banner ──────────────────────────────────────────────────────────
if ($config.notify.terminal) {
    $prefix = switch ($Event) {
        "done"       { "[+]" }
        "question"   { "[?]" }
        "permission" { "[!]" }
        "input"      { "[>]" }
        "tool"       { "[-]" }
        default      { "[*]" }
    }

    $labelColor = switch ($Event) {
        "done"       { "Green" }
        "question"   { "Yellow" }
        "permission" { "Red" }
        "input"      { "Cyan" }
        "tool"       { "DarkGray" }
        default      { "White" }
    }

    Write-Host ""
    if ($Detail) {
        Write-Host "  $prefix " -ForegroundColor $labelColor -NoNewline
        Write-Host "claude " -ForegroundColor DarkGray -NoNewline
        Write-Host $Detail -ForegroundColor White
    } else {
        Write-Host "  $prefix " -ForegroundColor $labelColor -NoNewline
        Write-Host "claude" -ForegroundColor DarkGray
    }

    if ($Message) {
        Write-Host "     $Message" -ForegroundColor Gray
    }
    Write-Host ""
}

# ── Toast notification (async - does not block hook exit) ────────────────────
if ($config.toast.enabled) {
    $toastLabel = switch ($Event) {
        "done"       { "Claude - Done" }
        "question"   { "Claude - Question" }
        "permission" { "Claude - Authorization Required" }
        "input"      { "Claude - Needs Input" }
        "tool"       { "Claude - $Detail" }
        default      { "Claude" }
    }

    $toastBody = if ($Detail -and $Event -ne "tool") { "$Message`n$Detail" } else { $Message }

    $toastScript = Join-Path $PSScriptRoot "toast.ps1"
    $titleArg    = $toastLabel -replace '"', '\"'
    $bodyArg     = $toastBody  -replace '"', '\"'

    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        "-NoProfile",
        "-NonInteractive",
        "-File", "`"$toastScript`"",
        "-Title", "`"$titleArg`"",
        "-Body",  "`"$bodyArg`""
    )
}