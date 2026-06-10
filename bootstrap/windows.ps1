# =============================================================================
# bootstrap/windows.ps1 — Windows host
#
# User-scope only; idempotent; safe to re-run. Phases (mirrored by
# bootstrap/linux.sh):
#
#   1. detect — locate the repo (no persistent env vars are written;
#               powershell/profile.ps1 self-locates via $PSScriptRoot)
#   2. tools  — PowerShell 7 + Starship (winget --scope user),
#               MesloLGS NF (per-user font dir), PSReadLine + Terminal-Icons
#   3. link   — source line in the per-user $PROFILE files
#   4. shell  — Windows Terminal One Dark Pro fragment
#
# UAC only appears if winget cannot satisfy a package in user scope.
# =============================================================================
#Requires -Version 5.1

$ErrorActionPreference = 'Stop'

function Log  { param($m) Write-Host "> $m" -ForegroundColor Cyan }
function Ok   { param($m) Write-Host "+ $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "! $m" -ForegroundColor Yellow }

# -----------------------------------------------------------------------------
# 1. detect
# -----------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dotfiles  = (Resolve-Path (Join-Path $ScriptDir '..')).Path
if (-not (Test-Path (Join-Path $Dotfiles 'powershell\profile.ps1'))) {
    throw "Repo not found around $ScriptDir"
}
Log "Using DOTFILES = $Dotfiles"

# -----------------------------------------------------------------------------
# 2. tools
# -----------------------------------------------------------------------------
foreach ($pkg in @(
    @{ Cmd = 'pwsh';     Id = 'Microsoft.PowerShell' },
    @{ Cmd = 'starship'; Id = 'Starship.Starship' }
)) {
    if (Get-Command $pkg.Cmd -ErrorAction SilentlyContinue) {
        Ok "$($pkg.Cmd) already present."
    } else {
        Log "Installing $($pkg.Id) via winget (user scope)..."
        winget install --id $pkg.Id --scope user --silent `
            --accept-source-agreements --accept-package-agreements
        Ok "$($pkg.Id) installed."
    }
}

Log "Installing MesloLGS NF (per-user)..."
$fontFiles = @(
    'MesloLGS NF Regular.ttf',
    'MesloLGS NF Bold.ttf',
    'MesloLGS NF Italic.ttf',
    'MesloLGS NF Bold Italic.ttf'
)
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$fontReg = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
foreach ($f in $fontFiles) {
    $dest = Join-Path $fontDir $f
    if (Test-Path $dest) { Ok "  $f already installed."; continue }
    $url = 'https://github.com/romkatv/powerlevel10k-media/raw/master/' + [uri]::EscapeUriString($f)
    Log "  downloading $f ..."
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    $regName = ([IO.Path]::GetFileNameWithoutExtension($f)) + ' (TrueType)'
    New-ItemProperty -Path $fontReg -Name $regName -Value $dest -PropertyType String -Force | Out-Null
}
Ok "MesloLGS NF installed."

Log "Installing PowerShell modules (CurrentUser scope)..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($mod in @('PSReadLine', 'Terminal-Icons')) {
    if (Get-Module -ListAvailable -Name $mod) {
        Ok "  $mod already present."
    } else {
        Install-Module -Name $mod -Scope CurrentUser -Force -AllowClobber
        Ok "  installed $mod."
    }
}

# -----------------------------------------------------------------------------
# 3. link — one AllHosts profile per PowerShell edition (pwsh + 5.1). Both
# load Documents\<edition>\profile.ps1 for every host, so the host-specific
# Microsoft.PowerShell_profile.ps1 variants are unnecessary.
# -----------------------------------------------------------------------------
Log "Wiring `$PROFILE -> dotfiles profile.ps1..."
# Resolve the real Documents folder (honors OneDrive / Known Folder redirection).
$documents = [Environment]::GetFolderPath('MyDocuments')
if ([string]::IsNullOrWhiteSpace($documents)) {
    $documents = Join-Path $HOME 'Documents'
    Warn "  Could not resolve MyDocuments; falling back to $documents"
}

$profilePaths = @(
    (Join-Path $documents 'PowerShell\profile.ps1'),
    (Join-Path $documents 'WindowsPowerShell\profile.ps1'),
    $PROFILE.CurrentUserAllHosts
) | Where-Object { $_ } | Select-Object -Unique

$dotProfile = Join-Path $Dotfiles 'powershell\profile.ps1'
$block      = "# Loaded by dotfiles bootstrap`r`n. `"$dotProfile`"`r`n"

foreach ($p in $profilePaths) {
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    $existing = ''
    if (Test-Path $p) {
        $existing = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        if ($null -eq $existing) { $existing = '' }
    }
    if ($existing -match [regex]::Escape($dotProfile)) {
        Ok "  already wired: $p"
        continue
    }
    if ([string]::IsNullOrWhiteSpace($existing)) {
        Set-Content -LiteralPath $p -Value $block -Encoding UTF8 -Force
    } else {
        $sep = if ($existing.EndsWith("`n")) { '' } else { "`r`n" }
        Add-Content -LiteralPath $p -Value ($sep + $block) -Encoding UTF8
    }
    Ok "  wired $p"
}

# -----------------------------------------------------------------------------
# 4. shell — Windows Terminal fragment (color scheme, no settings.json edits)
# -----------------------------------------------------------------------------
$fragmentSrc = Join-Path $Dotfiles 'windows-terminal\fragment.json'
$fragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\dotfiles-onedarkpro'
New-Item -ItemType Directory -Force -Path $fragmentDir | Out-Null
Copy-Item -Force $fragmentSrc (Join-Path $fragmentDir 'onedarkpro.json')
Ok "Windows Terminal fragment installed."

Write-Host ''
Ok 'Bootstrap complete.'
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host '  1. Close and reopen Windows Terminal.'
Write-Host '  2. Settings -> Defaults -> Appearance: scheme "One Dark Pro", font "MesloLGS NF".'
Write-Host '  3. (Optional) Set the default profile to PowerShell 7 (pwsh).'
Write-Host '  4. Updates apply automatically (<= 6h lag); force one with: dotfiles-sync'
