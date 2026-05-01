#Requires -Version 5.1
<#
.SYNOPSIS
    Windows installer for bash-config (Git aliases, SSH config, SK keys).

.DESCRIPTION
    Sets up the portable parts of bash-config on Windows:
      - Git configuration (aliases, settings, user identity via includes)
      - SSH configuration (copies secrets/ssh_config)
      - FIDO2/SK SSH key handles (copies from secrets/sk_ssh_handles/)

    Safe to re-run — validates current state and only fixes what's wrong.

.PARAMETER Specialisation
    Which gitconfig specialisation to use (diamond, frostpaw).
    If omitted, you'll be prompted to choose.

.PARAMETER DryRun
    Show what would be done without making changes.

.EXAMPLE
    .\install_windows.ps1
    .\install_windows.ps1 -Specialisation diamond
    .\install_windows.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet("diamond", "frostpaw")]
    [string]$Specialisation,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# CONSTANTS
# ==============================================================================
$ConfigRepo = $PSScriptRoot
$SshDir = Join-Path $env:USERPROFILE ".ssh"
$GitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Managed block markers (for .gitconfig)
$BlockStart = "# >>> bash-config initialize >>>"
$BlockEnd   = "# <<< bash-config initialize <<<"

# ==============================================================================
# LOGGING
# ==============================================================================
function Write-Status  { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Msg) Write-Host "[OK]   $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red }
function Write-Dry     { param([string]$Msg) Write-Host "[DRY]  $Msg" -ForegroundColor Magenta }

# ==============================================================================
# PREREQUISITES
# ==============================================================================
function Test-Prerequisites {
    Write-Status "Checking prerequisites..."
    $ok = $true

    # Git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitVer = (git --version) -replace 'git version ', ''
        Write-Ok "Git found: $gitVer"
    } else {
        Write-Err "Git not found. Install from https://git-scm.com/download/win"
        $ok = $false
    }

    # OpenSSH
    if (Get-Command ssh -ErrorAction SilentlyContinue) {
        Write-Ok "OpenSSH found"
    } else {
        Write-Err "OpenSSH not found. Enable it in Settings > Apps > Optional Features > OpenSSH Client"
        $ok = $false
    }

    # Secrets submodule
    $secretsDir = Join-Path $ConfigRepo "secrets"
    if (Test-Path (Join-Path $secretsDir "ssh_config")) {
        Write-Ok "Secrets submodule populated"
    } else {
        Write-Warn "secrets/ssh_config not found — run 'git submodule update --init --recursive' first"
        $ok = $false
    }

    return $ok
}

# ==============================================================================
# SPECIALISATION SELECTION
# ==============================================================================
function Select-Specialisation {
    # Find available specialisations (those with a gitconfig_* file, excluding base)
    $available = Get-ChildItem (Join-Path $ConfigRepo "configs" "gitconfig_*") |
        Where-Object { $_.Name -ne "gitconfig_base" } |
        ForEach-Object { $_.Name -replace '^gitconfig_', '' }

    if ($available.Count -eq 0) {
        Write-Err "No specialisation gitconfigs found in configs/"
        exit 1
    }

    Write-Host ""
    Write-Host "Which specialisation are you setting up?" -ForegroundColor White
    for ($i = 0; $i -lt $available.Count; $i++) {
        Write-Host "  [$($i + 1)] $($available[$i])"
    }
    Write-Host ""

    do {
        $choice = Read-Host "Enter number (1-$($available.Count))"
    } while (-not ($choice -match '^\d+$') -or [int]$choice -lt 1 -or [int]$choice -gt $available.Count)

    return $available[[int]$choice - 1]
}

# ==============================================================================
# GIT CONFIGURATION
# ==============================================================================
function Install-GitConfig {
    param([string]$Spec)

    Write-Status "Setting up Git configuration for '$Spec'..."

    $templatePath = Join-Path $ConfigRepo "configs" "gitconfig_$Spec"
    if (-not (Test-Path $templatePath)) {
        Write-Err "Specialisation gitconfig not found: $templatePath"
        return $false
    }

    # Read the template and resolve $BASH_CONFIG_DIR to the repo path (forward slashes for Git)
    $repoPathGit = $ConfigRepo -replace '\\', '/'
    $resolvedContent = (Get-Content $templatePath -Raw) -replace [regex]::Escape('$BASH_CONFIG_DIR'), $repoPathGit

    # Strip any leading comments from the template — we wrap it in our own block
    # Keep only the [include] / [includeIf] sections
    $configLines = $resolvedContent -split "`r?`n" |
        Where-Object { $_ -match '^\[' -or $_ -match '^\s+path\s*=' -or $_ -eq '' }

    $block = @(
        ""
        $BlockStart
        "# !! This block is managed by the bash-config Windows installer !!"
        "# !! Specialisation: $Spec | Generated: $Timestamp !!"
        ""
    )
    $block += $configLines
    $block += @(
        $BlockEnd
        ""
    )
    $newBlock = $block -join "`n"

    # Handle existing .gitconfig
    if (Test-Path $GitConfigPath) {
        $existing = Get-Content $GitConfigPath -Raw

        if ($existing -match [regex]::Escape($BlockStart)) {
            # Replace existing managed block
            $pattern = "(?s)" + [regex]::Escape($BlockStart) + ".*?" + [regex]::Escape($BlockEnd) + "`r?`n?"
            $updated = [regex]::Replace($existing, $pattern, "")

            # Check if content actually changed by comparing what we'd write
            $withBlock = $updated.TrimEnd() + "`n" + $newBlock

            # Re-read to compare (ignore the generated timestamp line)
            $currentBlock = [regex]::Match($existing, $pattern).Value
            $stripTimestamp = { param($s) ($s -split "`r?`n" | Where-Object { $_ -notmatch '# !! Specialisation:' }) -join "`n" }
            if ((& $stripTimestamp $currentBlock).Trim() -eq (& $stripTimestamp $newBlock).Trim()) {
                Write-Ok "Git config already up to date for '$Spec'"
                return $true
            }

            if ($DryRun) {
                Write-Dry "Would update managed block in $GitConfigPath"
                return $true
            }

            # Backup before modifying
            $backup = "$GitConfigPath.backup.$Timestamp"
            Copy-Item $GitConfigPath $backup
            Write-Status "Backed up existing .gitconfig to $backup"

            [System.IO.File]::WriteAllText($GitConfigPath, $withBlock, [System.Text.UTF8Encoding]::new($false))
            Write-Ok "Updated managed block in .gitconfig"
            return $true
        }

        # No existing block — append
        if ($DryRun) {
            Write-Dry "Would append managed block to $GitConfigPath"
            return $true
        }

        $backup = "$GitConfigPath.backup.$Timestamp"
        Copy-Item $GitConfigPath $backup
        Write-Status "Backed up existing .gitconfig to $backup"

        [System.IO.File]::AppendAllText($GitConfigPath, $newBlock, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "Appended managed block to .gitconfig"
        return $true
    }

    # No .gitconfig at all
    if ($DryRun) {
        Write-Dry "Would create $GitConfigPath with managed block"
        return $true
    }

    [System.IO.File]::WriteAllText($GitConfigPath, $newBlock, [System.Text.UTF8Encoding]::new($false))
    Write-Ok "Created .gitconfig with managed block"
    return $true
}

# ==============================================================================
# SSH CONFIGURATION
# ==============================================================================
function Set-SshPermissions {
    param([string]$Path)

    # Remove inherited ACLs and set owner-only access (equivalent to chmod 600)
    $acl = Get-Acl $Path
    $acl.SetAccessRuleProtection($true, $false)  # Disable inheritance, remove inherited rules
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
    $ownerRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $env:USERNAME, "FullControl", "Allow"
    )
    $acl.AddAccessRule($ownerRule)
    Set-Acl $Path $acl
}

function Install-SshConfig {
    Write-Status "Setting up SSH configuration..."

    $sourceConfig = Join-Path $ConfigRepo "secrets" "ssh_config"
    $targetConfig = Join-Path $SshDir "config"

    if (-not (Test-Path $sourceConfig)) {
        Write-Warn "secrets/ssh_config not found — skipping SSH config"
        return $false
    }

    # Ensure .ssh directory exists
    if (-not (Test-Path $SshDir)) {
        if ($DryRun) {
            Write-Dry "Would create $SshDir"
        } else {
            New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
            Write-Status "Created $SshDir"
        }
    }

    # Compare content if target exists
    if (Test-Path $targetConfig) {
        $sourceHash = (Get-FileHash $sourceConfig -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash $targetConfig -Algorithm SHA256).Hash

        if ($sourceHash -eq $targetHash) {
            Write-Ok "SSH config already up to date"
            return $true
        }

        if ($DryRun) {
            Write-Dry "Would replace $targetConfig (content differs)"
            return $true
        }

        $backup = "$targetConfig.backup.$Timestamp"
        Copy-Item $targetConfig $backup
        Write-Status "Backed up existing SSH config to $backup"
    } elseif ($DryRun) {
        Write-Dry "Would copy SSH config to $targetConfig"
        return $true
    }

    Copy-Item $sourceConfig $targetConfig -Force
    Set-SshPermissions $targetConfig
    Write-Ok "SSH config installed to $targetConfig"
    return $true
}

# ==============================================================================
# SK SSH KEY HANDLES
# ==============================================================================
function Install-SkSshHandles {
    Write-Status "Setting up SK SSH key handles..."

    $skDir = Join-Path $ConfigRepo "secrets" "sk_ssh_handles"
    if (-not (Test-Path $skDir)) {
        Write-Warn "secrets/sk_ssh_handles/ not found — skipping SK keys"
        return $false
    }

    $handles = Get-ChildItem $skDir -File | Where-Object {
        $_.Name -match '^id_(ed25519|ecdsa)_sk_'
    }

    if ($handles.Count -eq 0) {
        Write-Status "No SK key handles found in secrets/sk_ssh_handles/"
        return $true
    }

    # Ensure .ssh directory exists
    if (-not (Test-Path $SshDir)) {
        if ($DryRun) {
            Write-Dry "Would create $SshDir"
        } else {
            New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
        }
    }

    $copied = 0
    $skipped = 0
    $updated = 0

    foreach ($handle in $handles) {
        $target = Join-Path $SshDir $handle.Name

        if (Test-Path $target) {
            $sourceHash = (Get-FileHash $handle.FullName -Algorithm SHA256).Hash
            $targetHash = (Get-FileHash $target -Algorithm SHA256).Hash

            if ($sourceHash -eq $targetHash) {
                $skipped++
                continue
            }

            # Content differs — update it
            if ($DryRun) {
                Write-Dry "Would update $($handle.Name) (content differs)"
                $updated++
                continue
            }

            Copy-Item $handle.FullName $target -Force
            # Set permissions only on private keys (not .pub)
            if ($handle.Name -notmatch '\.pub$') {
                Set-SshPermissions $target
            }
            $updated++
        } else {
            if ($DryRun) {
                Write-Dry "Would copy $($handle.Name)"
                $copied++
                continue
            }

            Copy-Item $handle.FullName $target
            if ($handle.Name -notmatch '\.pub$') {
                Set-SshPermissions $target
            }
            $copied++
        }
    }

    if ($copied -gt 0)  { Write-Ok "Copied $copied new SK key handle(s)" }
    if ($updated -gt 0) { Write-Ok "Updated $updated changed SK key handle(s)" }
    if ($skipped -gt 0) { Write-Ok "$skipped SK key handle(s) already up to date" }

    return $true
}

# ==============================================================================
# VALIDATION (post-install check)
# ==============================================================================
function Test-Installation {
    Write-Host ""
    Write-Status "Validating installation..."
    $ok = $true

    # Git config includes
    if (Test-Path $GitConfigPath) {
        $content = Get-Content $GitConfigPath -Raw
        if ($content -match [regex]::Escape($BlockStart)) {
            # Verify the included files actually exist
            $includes = [regex]::Matches($content, 'path\s*=\s*(.+)') | ForEach-Object {
                $_.Groups[1].Value.Trim()
            }
            foreach ($inc in $includes) {
                # Resolve ~ to home
                $resolved = $inc -replace '^~', $env:USERPROFILE -replace '/', '\'
                if (-not (Test-Path $resolved)) {
                    Write-Warn "Git include target missing: $inc"
                    $ok = $false
                }
            }
            if ($ok) { Write-Ok "Git config includes all resolve correctly" }
        } else {
            Write-Warn ".gitconfig exists but has no managed block"
            $ok = $false
        }
    } else {
        Write-Warn ".gitconfig not found"
        $ok = $false
    }

    # SSH config
    $sshConfig = Join-Path $SshDir "config"
    if (Test-Path $sshConfig) {
        Write-Ok "SSH config present at $sshConfig"
    } else {
        Write-Warn "SSH config not found"
        $ok = $false
    }

    # SK handles
    $skCount = (Get-ChildItem $SshDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^id_(ed25519|ecdsa)_sk_' }).Count
    if ($skCount -gt 0) {
        Write-Ok "$skCount SK key handle(s) present in $SshDir"
    } else {
        Write-Warn "No SK key handles found in $SshDir"
    }

    # Git identity check
    try {
        $userName = git config --global user.name 2>$null
        $userEmail = git config --global user.email 2>$null
        if ($userName -and $userEmail) {
            Write-Ok "Git identity: $userName <$userEmail>"
        } else {
            Write-Warn "Git user.name or user.email not resolved (check includes)"
        }
    } catch {
        Write-Warn "Could not query Git config"
    }

    return $ok
}

# ==============================================================================
# MAIN
# ==============================================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor White
Write-Host "  bash-config Windows Installer" -ForegroundColor White
Write-Host "============================================" -ForegroundColor White
Write-Host ""

if ($DryRun) {
    Write-Dry "Dry run mode — no changes will be made"
    Write-Host ""
}

# 1. Prerequisites
if (-not (Test-Prerequisites)) {
    Write-Host ""
    Write-Err "Prerequisites not met. Fix the above issues and try again."
    exit 1
}

# 2. Specialisation
if (-not $Specialisation) {
    $Specialisation = Select-Specialisation
}
Write-Status "Using specialisation: $Specialisation"

# 3. Install
Write-Host ""
$gitOk = Install-GitConfig $Specialisation
$sshOk = Install-SshConfig
$skOk  = Install-SkSshHandles

# 4. Validate
$valid = Test-Installation

# 5. Summary
Write-Host ""
if ($DryRun) {
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "  Dry run complete — no changes were made" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
} elseif ($valid) {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Install complete!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
} else {
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host "  Install finished with warnings (see above)" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow
}
Write-Host ""
