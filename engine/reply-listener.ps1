<#
.SYNOPSIS
    Background reply listener for claude-herald.
    Polls ntfy for messages on the reply topic, then auto-pastes into the active terminal.
#>

$root       = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config.json"
$logPath    = Join-Path $root "herald.log"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.mobile.enabled) { exit 0 }

$server      = $config.mobile.ntfy_server
$replyTopic  = $config.mobile.reply_topic
$token       = $config.mobile.ntfy_token

if ([string]::IsNullOrWhiteSpace($replyTopic)) { exit 0 }

# Windows API for window focus and SendKeys
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
Add-Type -AssemblyName System.Windows.Forms

function Send-ToTerminal([string]$Text) {
    # Find Claude Code / Windows Terminal window
    $targets = @("Windows PowerShell","WindowsTerminal","claude","bash")
    $win = $null
    foreach ($t in $targets) {
        $proc = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.Name -match $t -or $_.MainWindowTitle -match $t) } | Select-Object -First 1
        if ($proc) { $win = $proc; break }
    }

    if ($win) {
        [WinFocus]::ShowWindow($win.MainWindowHandle, 9) | Out-Null   # SW_RESTORE
        [WinFocus]::SetForegroundWindow($win.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Clipboard]::SetText($Text)
        [System.Windows.Forms.SendKeys]::SendWait("^v")   # Ctrl+V paste
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return $true
    }
    return $false
}

function Show-ReplyToast([string]$Text) {
    $toastScript = Join-Path $root "engine\toast.ps1"
    if (Test-Path $toastScript) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            "-NoProfile","-NonInteractive",
            "-File","`"$toastScript`"",
            "-Title","Claude - Reply received",
            "-Body","`"$Text`""
        )
    }
}

$headers = @{}
if ($token) { $headers["Authorization"] = "Bearer $token" }

$since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

# Write PID so herald can check if we're running
$PID | Set-Content (Join-Path $root ".reply-listener-pid") -Force

while ($true) {
    Start-Sleep -Seconds 4

    try {
        $url  = "$server/$replyTopic/json?poll=1&since=$since"
        $resp = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -ErrorAction Stop
        $lines = $resp.Content -split "`n" | Where-Object { $_.Trim() }

        foreach ($line in $lines) {
            try {
                $msg = $line | ConvertFrom-Json
                if ($msg.event -eq "message" -and $msg.message) {
                    $text  = $msg.message.Trim()
                    $since = $msg.time + 1

                    # Map shorthand replies
                    $text = switch ($text.ToLower()) {
                        "yes"     { "yes" }
                        "no"      { "no" }
                        "approve" { "yes" }
                        "deny"    { "no" }
                        "y"       { "yes" }
                        "n"       { "no" }
                        default   { $text }
                    }

                    $pasted = Send-ToTerminal $text
                    if (-not $pasted) {
                        # Couldn't find terminal - show toast with the text
                        Show-ReplyToast $text
                        [System.Windows.Forms.Clipboard]::SetText($text)
                    }

                    Add-Content $logPath "[$(Get-Date -f 'HH:mm:ss')] reply-listener: received '$text' pasted=$pasted"
                }
            } catch { }
        }
    } catch {
        # ntfy unreachable - wait longer before retry
        Start-Sleep -Seconds 10
    }
}