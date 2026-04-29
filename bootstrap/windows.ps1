# =============================================================================
# bootstrap/windows.ps1
# Idempotent installer for Windows: PS7 + Starship + MesloLGS NF +
# PSReadLine + Terminal-Icons + Windows Terminal One Dark Pro fragment
#
# No-admin friendly: every action targets user scope (winget --scope user,
# Install-Module -Scope CurrentUser, %LOCALAPPDATA% font dir + WT fragments).
# UAC will only appear if winget can't satisfy a package in user scope.
# =============================================================================
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

function Log  { param($m) Write-Host "▶ $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "✓ $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "! $m" -ForegroundColor Yellow }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir   = (Resolve-Path (Join-Path $ScriptDir '..')).Path
if (-not $env:DOTFILES) {
    [Environment]::SetEnvironmentVariable('DOTFILES', $RepoDir, 'User')
    $env:DOTFILES = $RepoDir
}
Log "DOTFILES = $env:DOTFILES"

# 1. PowerShell 7
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    Log "Installing PowerShell 7 via winget (user scope)…"
    winget install --id Microsoft.PowerShell --scope user --silent `
        --accept-source-agreements --accept-package-agreements
    Ok "PowerShell 7 installed."
} else {
    Ok "PowerShell 7 already present."
}

# 2. Starship
if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
    Log "Installing Starship via winget (user scope)…"
    winget install --id Starship.Starship --scope user --silent `
        --accept-source-agreements --accept-package-agreements
    Ok "Starship installed."
} else {
    Ok "Starship already present."
}

# 3. MesloLGS NF — per-user, no admin
Log "Installing MesloLGS NF (per-user)…"
$fontFiles = @(
    'MesloLGS NF Regular.ttf',
    'MesloLGS NF Bold.ttf',
    'MesloLGS NF Italic.ttf',
    'MesloLGS NF Bold Italic.ttf'
)
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
$fontReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

foreach ($f in $fontFiles) {
    $dest = Join-Path $fontDir $f
    if (Test-Path $dest) { Ok "  $f already installed."; continue }
    $url = "https://github.com/romkatv/powerlevel10k-media/raw/master/" + [uri]::EscapeUriString($f)
    Log "  downloading $f …"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    $regName = ([IO.Path]::GetFileNameWithoutExtension($f)) + ' (TrueType)'
    New-ItemProperty -Path $fontReg -Name $regName -Value $dest -PropertyType String -Force | Out-Null
}
Ok "MesloLGS NF installed."

# 4. PowerShell modules
Log "Installing PowerShell modules…"
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($mod in @('PSReadLine','Terminal-Icons')) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
        Ok "  installed $mod."
    } else {
        Ok "  $mod already present."
    }
}

# 5. Wire $PROFILE
# Resolve the user's real Documents folder (honors OneDrive / Known Folder
# redirection to non-default drives, e.g. D:\documents) instead of assuming
# it lives under $HOME.
Log "Wiring `$PROFILE → dotfiles profile.ps1…"
$documents = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($documents)) {
    $documents = Join-Path $HOME 'Documents'
    Warn "  Could not resolve MyDocuments via shell; falling back to $documents"
}
Log "  Documents folder: $documents"

$profilePaths = @(
    # PowerShell 7+ (pwsh) — both AllHosts and the host-specific profile
    (Join-Path $documents 'PowerShell\profile.ps1'),
    (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'),
    # Windows PowerShell 5.1
    (Join-Path $documents 'WindowsPowerShell\profile.ps1'),
    (Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    # Whatever the currently running host reports (covers ISE, VSCode host, etc.)
    $PROFILE.CurrentUserAllHosts
) | Where-Object { $_ } | Select-Object -Unique

$dotProfile = Join-Path $env:DOTFILES 'powershell\profile.ps1'
$sourceLine = ". `"$dotProfile`""
$block      = "# Loaded by dotfiles bootstrap`r`n$sourceLine`r`n"

foreach ($p in $profilePaths) {
    $dir = Split-Path $p
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    # Read existing content (if any) without creating the file first.
    $existing = ''
    if (Test-Path $p) {
        $existing = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        if ($null -eq $existing) { $existing = '' }
    }

    if ($existing -match [regex]::Escape($dotProfile)) {
        Ok "  already wired: $p"
        continue
    }

    try {
        if ([string]::IsNullOrWhiteSpace($existing)) {
            # Brand new (or empty) profile — write the block atomically as UTF-8.
            Set-Content -LiteralPath $p -Value $block -Encoding UTF8 -Force
        } else {
            # Existing profile with unrelated content — append, preserving it.
            $sep = if ($existing.EndsWith("`n")) { '' } else { "`r`n" }
            Add-Content -LiteralPath $p -Value ($sep + $block) -Encoding UTF8
        }

        # Verify the write actually landed.
        $verify = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        if ($verify -match [regex]::Escape($dotProfile)) {
            Ok "  wired $p"
        } else {
            Warn "  wrote $p but source line not detected on re-read"
        }
    } catch {
        Warn "  failed to wire $p — $($_.Exception.Message)"
    }
}

# 6. Windows Terminal fragment
$fragmentSrc = Join-Path $env:DOTFILES 'windows-terminal\fragment.json'
if (Test-Path $fragmentSrc) {
    $fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\dotfiles-onedarkpro'
    New-Item -ItemType Directory -Force -Path $fragmentDir | Out-Null
    Copy-Item -Force $fragmentSrc (Join-Path $fragmentDir 'onedarkpro.json')
    Ok "Windows Terminal fragment installed → $fragmentDir"
} else {
    Warn "Windows Terminal fragment not found at $fragmentSrc"
}

Write-Host ""
Ok "Bootstrap complete."
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and reopen Windows Terminal."
Write-Host "  2. Settings → Defaults → Appearance:"
Write-Host "       - Color scheme:  One Dark Pro"
Write-Host "       - Font face:     MesloLGS NF"
Write-Host "  3. (Optional) Set default profile to PowerShell 7 (pwsh)."
Write-Host "  4. Updates from GitHub apply automatically (≤ 6h lag); force one with: dotfiles-sync"
