#Requires -Version 5.1
<#
.SYNOPSIS
    Windows uninstaller for bash-config.

.DESCRIPTION
    Removes the components installed by install_windows.ps1:
      - Managed block from ~/.gitconfig
      - SSH config from ~/.ssh/config
      - SK SSH key handles from ~/.ssh/

    Backups are created before any destructive changes.

.PARAMETER DryRun
    Show what would be done without making changes.

.EXAMPLE
    .\uninstall_windows.ps1
    .\uninstall_windows.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$SshDir = Join-Path $env:USERPROFILE ".ssh"
$GitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$BlockStart = "# >>> bash-config initialize >>>"
$BlockEnd   = "# <<< bash-config initialize <<<"

function Write-Status  { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Msg) Write-Host "[OK]   $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Dry     { param([string]$Msg) Write-Host "[DRY]  $Msg" -ForegroundColor Magenta }

# ==============================================================================
# GIT CONFIG
# ==============================================================================
function Uninstall-GitConfig {
    Write-Status "Checking .gitconfig..."

    if (-not (Test-Path $GitConfigPath)) {
        Write-Status "No .gitconfig found (nothing to do)"
        return
    }

    $content = Get-Content $GitConfigPath -Raw
    if ($content -notmatch [regex]::Escape($BlockStart)) {
        Write-Status "No managed block found in .gitconfig (nothing to do)"
        return
    }

    if ($DryRun) {
        Write-Dry "Would remove managed block from $GitConfigPath"
        return
    }

    $backup = "$GitConfigPath.backup.$Timestamp"
    Copy-Item $GitConfigPath $backup
    Write-Status "Backed up .gitconfig to $backup"

    $pattern = "(?s)`r?`n?" + [regex]::Escape($BlockStart) + ".*?" + [regex]::Escape($BlockEnd) + "`r?`n?"
    $cleaned = [regex]::Replace($content, $pattern, "`n")
    $cleaned = $cleaned.TrimEnd() + "`n"

    [System.IO.File]::WriteAllText($GitConfigPath, $cleaned, [System.Text.UTF8Encoding]::new($false))

    # If the file is now effectively empty, remove it
    $remaining = (Get-Content $GitConfigPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($remaining)) {
        Remove-Item $GitConfigPath
        Write-Ok "Removed empty .gitconfig"
    } else {
        Write-Ok "Removed managed block from .gitconfig (other content preserved)"
    }
}

# ==============================================================================
# SSH CONFIG
# ==============================================================================
function Uninstall-SshConfig {
    Write-Status "Checking SSH config..."

    $targetConfig = Join-Path $SshDir "config"
    if (-not (Test-Path $targetConfig)) {
        Write-Status "No SSH config found (nothing to do)"
        return
    }

    if ($DryRun) {
        Write-Dry "Would remove $targetConfig"
        return
    }

    $backup = "$targetConfig.backup.$Timestamp"
    Copy-Item $targetConfig $backup
    Write-Status "Backed up SSH config to $backup"

    Remove-Item $targetConfig
    Write-Ok "Removed SSH config"
}

# ==============================================================================
# SK SSH KEY HANDLES
# ==============================================================================
function Uninstall-SkSshHandles {
    Write-Status "Checking SK SSH key handles..."

    if (-not (Test-Path $SshDir)) {
        Write-Status "No .ssh directory found (nothing to do)"
        return
    }

    $handles = Get-ChildItem $SshDir -File | Where-Object {
        $_.Name -match '^id_(ed25519|ecdsa)_sk_'
    }

    if ($handles.Count -eq 0) {
        Write-Status "No SK key handles found (nothing to do)"
        return
    }

    Write-Warn "Found $($handles.Count) SK key handle(s) in $SshDir"
    if (-not $DryRun) {
        $confirm = Read-Host "Remove all SK key handles? (y/N)"
        if ($confirm -ne 'y') {
            Write-Status "Skipped SK key handle removal"
            return
        }
    }

    $removed = 0
    foreach ($handle in $handles) {
        if ($DryRun) {
            Write-Dry "Would remove $($handle.Name)"
        } else {
            Remove-Item $handle.FullName
        }
        $removed++
    }

    if (-not $DryRun) {
        Write-Ok "Removed $removed SK key handle(s)"
    }
}

# ==============================================================================
# MAIN
# ==============================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host "  bash-config Windows Uninstaller" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Dry "Dry run mode - no changes will be made"
    Write-Host ""
}

Uninstall-GitConfig
Uninstall-SshConfig
Uninstall-SkSshHandles

Write-Host ""
if ($DryRun) {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "  Dry run complete - no changes were made" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
} else {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Uninstall complete" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Backups were saved with timestamp $Timestamp" -ForegroundColor Gray
}
Write-Host ""
