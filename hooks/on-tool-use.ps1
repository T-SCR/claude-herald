<#
.SYNOPSIS
    Claude Code PostToolUse hook - terminal banner for significant tool events.
    Silent on high-frequency tools (Read, Grep, Glob, QMD).
#>

$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$linesPath    = Join-Path $root "voice\lines.json"
$notifyScript = Join-Path $root "engine\notify.ps1"

if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled)           { exit 0 }
if (-not $config.hooks.on_tool_use) { exit 0 }

$lines = Get-Content $linesPath -Raw | ConvertFrom-Json

# Read hook payload
$payload = $null
try {
    $raw = $input | Out-String
    if ($raw.Trim()) { $payload = $raw | ConvertFrom-Json }
} catch { exit 0 }

if (-not $payload) { exit 0 }

$toolName = $payload.tool_name

# Silent on noisy low-signal tools
$silentTools = @("Read","Glob","Grep","mcp__qmd__query","mcp__qmd__get",
                 "mcp__qmd__multi_get","ToolSearch","advisor")
if ($toolName -in $silentTools) { exit 0 }

$message = $null
$detail  = $null

switch -Regex ($toolName) {
    "^Write$" {
        $fp      = $payload.tool_input.file_path
        $detail  = if ($fp) { Split-Path $fp -Leaf } else { "file" }
        $pool    = $lines.tool.Write
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^Edit$" {
        $fp      = $payload.tool_input.file_path
        $detail  = if ($fp) { Split-Path $fp -Leaf } else { "file" }
        $pool    = $lines.tool.Edit
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^Bash$" {
        $cmd     = $payload.tool_input.command
        $detail  = if ($cmd -and $cmd.Length -gt 48) { $cmd.Substring(0,45) + "..." } else { $cmd }
        $pool    = $lines.tool.Bash
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^WebFetch$" {
        $pool    = $lines.tool.WebFetch
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^WebSearch$" {
        $pool    = $lines.tool.WebSearch
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^Agent$" {
        $pool    = $lines.tool.Agent
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    "^TodoWrite$" {
        $pool    = $lines.tool.TodoWrite
        $message = $pool[(Get-Random -Maximum $pool.Count)]
    }
    default {
        $message = "Operation complete."
        $detail  = $toolName
    }
}

if ($message) {
    & $notifyScript -Event "tool" -Message $message -Detail $detail
}