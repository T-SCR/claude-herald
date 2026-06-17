<#
.SYNOPSIS
    Mobile push via ntfy.sh with action buttons for two-way replies.
#>
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Body,
    [ValidateSet("min","low","default","high","urgent")][string]$Priority = "default"
)

$root       = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.mobile.enabled) { exit 0 }

$topic       = $config.mobile.ntfy_topic
$replyTopic  = $config.mobile.reply_topic
$server      = $config.mobile.ntfy_server
$token       = $config.mobile.ntfy_token

if ([string]::IsNullOrWhiteSpace($topic)) { exit 0 }

$headers = @{
    "Title"    = $Title
    "Priority" = $Priority
    "Tags"     = "robot,bell"
}

if ($token) { $headers["Authorization"] = "Bearer $token" }

# Add action buttons if reply topic is configured
if (-not [string]::IsNullOrWhiteSpace($replyTopic)) {
    $replyUrl = "$server/$replyTopic"

    if ($Title -match "Authorization|Permission") {
        # Permission: one-tap Approve / Deny buttons
        $headers["Actions"] = "http, Approve, $replyUrl, method=POST, body=yes; http, Deny, $replyUrl, method=POST, body=no"
    } elseif ($Title -match "Question|Input|Waiting") {
        # Question: View action opens ntfy publish page for free-form reply
        $headers["Actions"] = "view, Reply in app, $server/$replyTopic; http, Yes, $replyUrl, method=POST, body=yes; http, No, $replyUrl, method=POST, body=no"
    } else {
        $headers["Actions"] = "view, Open, $server/$replyTopic"
    }
}

try {
    Invoke-RestMethod -Uri "$server/$topic" -Method Post -Body $Body -Headers $headers -ErrorAction Stop | Out-Null
} catch {
    $_ | Out-File (Join-Path $root "herald.log") -Append
}

# Ensure reply listener is running (start it if not)
if (-not [string]::IsNullOrWhiteSpace($replyTopic)) {
    $pidFile     = Join-Path $root ".reply-listener-pid"
    $listenerScript = Join-Path $root "engine\reply-listener.ps1"
    $isRunning   = $false

    if (Test-Path $pidFile) {
        $savedPid = Get-Content $pidFile -Raw -ErrorAction SilentlyContinue
        if ($savedPid -and (Get-Process -Id $savedPid -ErrorAction SilentlyContinue)) {
            $isRunning = $true
        }
    }

    if (-not $isRunning) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-NonInteractive",
            "-File", "`"$listenerScript`""
        )
    }
}