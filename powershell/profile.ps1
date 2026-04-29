# =============================================================================
# PowerShell $PROFILE — managed by dotfiles repo
# =============================================================================

if (-not $env:DOTFILES) { $env:DOTFILES = Join-Path $HOME ".dotfiles" }

# Optional startup profiler: $env:PSPROFILE='1'; pwsh -NoLogo
if ($env:PSPROFILE) { $script:profileStart = Get-Date }

# UTF-8 — keeps Nerd Font glyphs rendering correctly
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# -----------------------------------------------------------------------------
# Background dotfiles sync
#   - Pulls origin at most once per DOTFILES_SYNC_INTERVAL seconds (default 6h)
#   - Runs as a fire-and-forget ThreadJob (or Job on PS5.1); never blocks
#   - Skips silently if working tree is dirty or merge isn't fast-forward
# Tunables:
#   $env:DOTFILES_SYNC = '0'            # disable
#   $env:DOTFILES_SYNC_INTERVAL = 3600  # seconds between pulls
# Force a foreground pull right after pushing: dotfiles-sync
# -----------------------------------------------------------------------------
function Invoke-DotfilesSync {
    if ($env:DOTFILES_SYNC -eq '0') { return }
    $repo = $env:DOTFILES
    if (-not (Test-Path (Join-Path $repo '.git'))) { return }

    $marker = Join-Path $env:LOCALAPPDATA 'dotfiles\last-pull'
    $interval = if ($env:DOTFILES_SYNC_INTERVAL -as [int]) {
        [int]$env:DOTFILES_SYNC_INTERVAL
    } else { 21600 }

    if (Test-Path $marker) {
        $age = ((Get-Date) - (Get-Item $marker).LastWriteTime).TotalSeconds
        if ($age -lt $interval) { return }
    }

    $null = New-Item -ItemType Directory -Force -Path (Split-Path $marker) -ErrorAction SilentlyContinue
    Set-Content -Path $marker -Value '' -NoNewline   # touch first so concurrent shells skip

    $sb = {
        param($r)
        Set-Location $r
        if (git status --porcelain 2>$null) { return }   # dirty — skip
        git fetch --quiet 2>$null
        git merge --ff-only --quiet '@{u}' 2>$null
    }
    if (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue) {
        $null = Start-ThreadJob -ScriptBlock $sb -ArgumentList $repo
    } else {
        $null = Start-Job -ScriptBlock $sb -ArgumentList $repo
    }
}

function dotfiles-sync {
    if (-not $env:DOTFILES) { Write-Error 'DOTFILES not set'; return }
    Push-Location $env:DOTFILES
    try { git pull --ff-only } finally { Pop-Location }
    $marker = Join-Path $env:LOCALAPPDATA 'dotfiles\last-pull'
    Set-Content -Path $marker -Value '' -NoNewline
}

Invoke-DotfilesSync

# -----------------------------------------------------------------------------
# PSReadLine — One Dark Pro palette, predictive autocomplete
# Use try/Import-Module instead of `Get-Module -ListAvailable` (which scans
# every module path; ~200–500ms on Windows). Import-Module is fast and either
# succeeds or throws.
# -----------------------------------------------------------------------------
try {
    Import-Module PSReadLine -ErrorAction Stop
    $psrlVersion = (Get-Module PSReadLine).Version

    if ($psrlVersion -ge [version]'2.2.0') {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle InlineView    -ErrorAction SilentlyContinue
    }
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # One Dark Pro colours
    $esc = [char]27
    Set-PSReadLineOption -Colors @{
        Command            = '#61afef'                       # blue
        Parameter          = '#c678dd'                       # purple
        Operator           = '#56b6c2'                       # cyan
        Variable           = '#e06c75'                       # red
        String             = '#98c379'                       # green
        Number             = '#d19a66'                       # orange
        Type               = '#e5c07b'                       # yellow
        Comment            = '#5c6370'                       # comment grey
        Keyword            = '#c678dd'                       # purple
        Error              = '#e06c75'                       # red
        InlinePrediction   = '#5c6370'                       # comment grey
        Selection          = "$esc[48;2;62;68;81m"           # #3e4451
    }

    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    if ($psrlVersion -ge [version]'2.2.0') {
        Set-PSReadLineKeyHandler -Chord Ctrl+Spacebar -Function AcceptSuggestion -ErrorAction SilentlyContinue
    }
} catch { }

try { Import-Module Terminal-Icons -ErrorAction Stop } catch { }

function ll { Get-ChildItem -Force @args }
function la { Get-ChildItem -Force @args }
function reload { . $PROFILE }

$localProfile = Join-Path (Split-Path $PROFILE) "profile.local.ps1"
if (Test-Path $localProfile) { . $localProfile }

# -----------------------------------------------------------------------------
# Starship prompt — must be last
# Cache `starship init powershell --print-full-init` to disk so we don't fork
# starship on every shell launch. Cache invalidates when the binary or the
# starship.toml mtime is newer than the cache file.
# -----------------------------------------------------------------------------
$starship = Get-Command starship -ErrorAction SilentlyContinue
if ($starship) {
    $env:STARSHIP_CONFIG = Join-Path $env:DOTFILES "starship\starship.toml"
    $cache    = Join-Path $env:LOCALAPPDATA 'starship\init.ps1'
    $cacheDir = Split-Path $cache

    $stale = $true
    if (Test-Path $cache) {
        $cacheTime  = (Get-Item $cache).LastWriteTime
        $binTime    = (Get-Item $starship.Source).LastWriteTime
        $configTime = if (Test-Path $env:STARSHIP_CONFIG) {
            (Get-Item $env:STARSHIP_CONFIG).LastWriteTime
        } else { [datetime]::MinValue }
        $stale = ($binTime -gt $cacheTime) -or ($configTime -gt $cacheTime)
    }
    if ($stale) {
        $null = New-Item -ItemType Directory -Force -Path $cacheDir -ErrorAction SilentlyContinue
        & $starship.Source init powershell --print-full-init | Set-Content -Path $cache
    }
    . $cache
}

if ($env:PSPROFILE) {
    $elapsed = ((Get-Date) - $script:profileStart).TotalMilliseconds
    Write-Host ("[profile] loaded in {0:N1} ms" -f $elapsed) -ForegroundColor DarkGray
}
