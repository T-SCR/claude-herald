<#
.SYNOPSIS
    claude-herald CLI - manage notification settings.

.EXAMPLE
    .\herald.ps1 --status
    .\herald.ps1 --test
    .\herald.ps1 --toggle terminal
    .\herald.ps1 --toggle toast
    .\herald.ps1 --toggle voice
    .\herald.ps1 --toggle mobile
    .\herald.ps1 --toggle tool-events
    .\herald.ps1 --toggle complete-push
    .\herald.ps1 --mute / --unmute
    .\herald.ps1 --profiles
    .\herald.ps1 --set-profile jarvis
    .\herald.ps1 --set-topic my-ntfy-topic
    .\herald.ps1 --voices
#>

param(
    [switch]$Status,
    [string]$Toggle,
    [switch]$Test,
    [switch]$Profiles,
    [string]$SetProfile,
    [string]$SetTopic,
    [string]$SetVoice,
    [switch]$Voices,
    [switch]$Mute,
    [switch]$Unmute,
    [switch]$Help
)

$configPath = Join-Path $PSScriptRoot "config.json"

function Get-Config { Get-Content $configPath -Raw | ConvertFrom-Json }
function Save-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}
function Write-Status($label, $value) {
    $icon  = if ($value) { "[ON] " } else { "[OFF]" }
    $color = if ($value) { "Green" } else { "DarkGray" }
    Write-Host "  $icon  $label" -ForegroundColor $color
}

$anyFlag = $Status -or $Toggle -or $Test -or $Profiles -or $SetProfile `
           -or $SetTopic -or $SetVoice -or $Voices -or $Mute -or $Unmute

if ($Help -or (-not $anyFlag)) {
    Write-Host ""
    Write-Host "claude-herald" -ForegroundColor Cyan
    Write-Host "Notification bridge for Claude Code" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\herald.ps1 --status                   See all settings"
    Write-Host "  .\herald.ps1 --test                     Fire a test notification"
    Write-Host "  .\herald.ps1 --toggle <feature>         Toggle on/off"
    Write-Host "  .\herald.ps1 --mute / --unmute          Quick voice mute (if voice enabled)"
    Write-Host "  .\herald.ps1 --profiles                 List voice profiles"
    Write-Host "  .\herald.ps1 --set-profile <name>       Switch voice profile"
    Write-Host "  .\herald.ps1 --voices                   List installed TTS voices"
    Write-Host "  .\herald.ps1 --set-topic <topic>        Enable mobile push"
    Write-Host ""
    Write-Host "Features to toggle:" -ForegroundColor Yellow
    Write-Host "  terminal      Styled banner in Claude Code terminal  [default: ON]"
    Write-Host "  toast         Windows toast popups                   [default: ON]"
    Write-Host "  voice         TTS voice announcements                [default: OFF]"
    Write-Host "  mobile        Phone push via ntfy.sh                 [default: OFF]"
    Write-Host "  tool-events   Notify on Write/Edit/Bash tool use"
    Write-Host "  complete-push Push to phone even on task-done"
    Write-Host "  tool-details  Include filename/cmd in notifications"
    Write-Host ""
    exit 0
}

if ($Status) {
    $cfg = Get-Config
    Write-Host ""
    Write-Host "claude-herald status" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor DarkGray
    Write-Status "Master switch        " $cfg.enabled
    Write-Host ""
    Write-Host "  Notifications:" -ForegroundColor DarkGray
    Write-Status "  Terminal banner    " $cfg.notify.terminal
    Write-Status "  Toast popups       " $cfg.toast.enabled
    Write-Status "  Toast on tools     " $cfg.toast.show_tool_events
    Write-Status "  Voice TTS          " $cfg.voice.enabled
    Write-Status "  Mobile push        " $cfg.mobile.enabled
    Write-Status "  Push on complete   " $cfg.mobile.push_on_complete
    Write-Host ""
    Write-Host "  Hooks:" -ForegroundColor DarkGray
    Write-Status "  On-stop hook       " $cfg.hooks.on_stop
    Write-Status "  On-tool-use hook   " $cfg.hooks.on_tool_use
    Write-Status "  Tool details       " $cfg.announcements.tool_details
    Write-Host ""

    # Active voice profile
    if ($cfg.voice.enabled -and $cfg.PSObject.Properties["profiles"] -and $cfg.voice.active_profile) {
        $p = $cfg.profiles.PSObject.Properties[$cfg.voice.active_profile]
        if ($p) {
            Write-Host "  Voice profile: $($cfg.voice.active_profile) - $($p.Value.description)" -ForegroundColor DarkGray
        }
    }

    $topic = if ($cfg.mobile.ntfy_topic) { $cfg.mobile.ntfy_topic } else { "(not set)" }
    Write-Host "  ntfy topic: $topic" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

if ($Profiles) {
    $cfg    = Get-Config
    $active = $cfg.voice.active_profile
    Write-Host ""
    Write-Host "Voice profiles:" -ForegroundColor Cyan
    $cfg.profiles.PSObject.Properties | ForEach-Object {
        $marker = if ($_.Name -eq $active) { " [ACTIVE]" } else { "" }
        $color  = if ($_.Name -eq $active) { "Green" } else { "White" }
        Write-Host "  $($_.Name)$marker" -ForegroundColor $color
        Write-Host "    $($_.Value.description)  rate=$($_.Value.rate)  vol=$($_.Value.volume)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Switch: .\herald.ps1 --set-profile <name>" -ForegroundColor Yellow
    Write-Host "Enable voice first: .\herald.ps1 --toggle voice" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

if ($SetProfile) {
    $cfg = Get-Config
    if (-not ($cfg.PSObject.Properties["profiles"] -and
              $cfg.profiles.PSObject.Properties[$SetProfile])) {
        $avail = ($cfg.profiles.PSObject.Properties | ForEach-Object { $_.Name }) -join ", "
        Write-Host "Profile '$SetProfile' not found. Available: $avail" -ForegroundColor Red
        exit 1
    }
    $cfg.voice.active_profile = $SetProfile
    Save-Config $cfg
    Write-Host "Profile set to: $SetProfile" -ForegroundColor Green
    exit 0
}

if ($Mute) {
    $cfg = Get-Config; $cfg.voice.enabled = $false; Save-Config $cfg
    Write-Host "Voice muted." -ForegroundColor Yellow; exit 0
}
if ($Unmute) {
    $cfg = Get-Config; $cfg.voice.enabled = $true; Save-Config $cfg
    Write-Host "Voice unmuted." -ForegroundColor Green; exit 0
}

if ($Toggle) {
    $cfg = Get-Config
    switch ($Toggle.ToLower()) {
        "terminal"      { $cfg.notify.terminal                = -not $cfg.notify.terminal;                $label = "Terminal banner" }
        "toast"         { $cfg.toast.enabled                  = -not $cfg.toast.enabled;                  $label = "Toast popups" }
        "voice"         { $cfg.voice.enabled                  = -not $cfg.voice.enabled;                  $label = "Voice TTS" }
        "mobile"        { $cfg.mobile.enabled                 = -not $cfg.mobile.enabled;                 $label = "Mobile push" }
        "tool-events"   { $cfg.toast.show_tool_events         = -not $cfg.toast.show_tool_events;         $label = "Toast on tool events" }
        "complete-push" { $cfg.mobile.push_on_complete        = -not $cfg.mobile.push_on_complete;        $label = "Push on complete" }
        "tool-details"  { $cfg.announcements.tool_details     = -not $cfg.announcements.tool_details;     $label = "Tool details" }
        default {
            Write-Host "Unknown feature: $Toggle. Run --help for list." -ForegroundColor Red; exit 1
        }
    }
    Save-Config $cfg
    $newVal = switch ($Toggle.ToLower()) {
        "terminal"      { $cfg.notify.terminal }
        "toast"         { $cfg.toast.enabled }
        "voice"         { $cfg.voice.enabled }
        "mobile"        { $cfg.mobile.enabled }
        "tool-events"   { $cfg.toast.show_tool_events }
        "complete-push" { $cfg.mobile.push_on_complete }
        "tool-details"  { $cfg.announcements.tool_details }
    }
    $state = if ($newVal) { "ON" } else { "OFF" }
    $color = if ($newVal) { "Green" } else { "Yellow" }
    Write-Host "$label $state." -ForegroundColor $color
    exit 0
}

if ($SetTopic) {
    $cfg = Get-Config
    $cfg.mobile.ntfy_topic = $SetTopic
    $cfg.mobile.enabled    = $true
    Save-Config $cfg
    Write-Host "Mobile topic: $SetTopic" -ForegroundColor Green
    Write-Host "Subscribe at: $($cfg.mobile.ntfy_server)/$SetTopic" -ForegroundColor Cyan
    exit 0
}

if ($Voices) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    Write-Host ""
    Write-Host "Installed TTS voices:" -ForegroundColor Cyan
    $synth.GetInstalledVoices() | ForEach-Object {
        $i = $_.VoiceInfo
        Write-Host "  $($i.Name)  [$($i.Gender), $($i.Culture)]" -ForegroundColor White
    }
    $synth.Dispose()
    Write-Host ""
    Write-Host "Add more: Settings > Time & language > Speech > Add voices" -ForegroundColor DarkGray
    exit 0
}

if ($SetVoice) {
    $cfg = Get-Config
    if ($cfg.PSObject.Properties["profiles"] -and $cfg.voice.active_profile) {
        $pName = $cfg.voice.active_profile
        if ($cfg.profiles.PSObject.Properties[$pName]) {
            $cfg.profiles.$pName.name = $SetVoice
            Save-Config $cfg
            Write-Host "Voice in '$pName' profile set to: $SetVoice" -ForegroundColor Green
            exit 0
        }
    }
    $cfg.voice.name = $SetVoice; Save-Config $cfg
    Write-Host "Voice set to: $SetVoice" -ForegroundColor Green
    exit 0
}

if ($Test) {
    $cfg          = Get-Config
    $notifyScript = Join-Path $PSScriptRoot "engine\notify.ps1"
    Write-Host ""
    Write-Host "Firing test notifications..." -ForegroundColor Cyan
    Write-Host "(terminal banner below, toast popup should appear)" -ForegroundColor DarkGray

    & $notifyScript -Event "done"       -Message "Process concluded. Standing by for your directive."
    Start-Sleep -Milliseconds 600
    & $notifyScript -Event "question"   -Message "There is something I need clarification on."
    Start-Sleep -Milliseconds 600
    & $notifyScript -Event "permission" -Message "Authorization required. Please review and respond."
    Start-Sleep -Milliseconds 600
    & $notifyScript -Event "tool"       -Message "File updated." -Detail "Skills.md"
    Write-Host "Test complete." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}