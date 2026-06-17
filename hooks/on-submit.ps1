<#
.SYNOPSIS
    UserPromptSubmit hook - stops the repeat alert when user responds.
#>
$root         = Split-Path $PSScriptRoot -Parent
$sentinelFile = Join-Path $root ".herald-alert"

if (Test-Path $sentinelFile) {
    Remove-Item $sentinelFile -Force -ErrorAction SilentlyContinue
}

# Pass through - do not block the prompt