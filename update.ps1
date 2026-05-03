#Requires -Version 5.1
<#
.SYNOPSIS
    agentpipe — Update Script (canonical update entry point) (Windows PowerShell).
.DESCRIPTION
    Equivalent to `.\install.ps1 -Update`. Forwards all extra args.
.EXAMPLE
    .\update.ps1                          # update for Claude Code
    .\update.ps1 -Target codex            # update for Codex CLI
    .\update.ps1 -NoClaudeMd              # skip baseline CLAUDE.md install on update
    .\update.ps1 -WithSoundHooks          # opt-in: Stop sound hook only during update
    .\update.ps1 -WithNotificationSound   # opt-in: Notification sound hook only during update
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$Install = Join-Path $ScriptDir "install.ps1"

# Forward to install.ps1 -Update <extra args>
$forwardArgs = @("-Update") + $Args
& $Install @forwardArgs
exit $LASTEXITCODE
