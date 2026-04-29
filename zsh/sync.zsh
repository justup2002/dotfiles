# =============================================================================
# Background dotfiles sync
#
# Pulls the dotfiles repo from origin at most once per DOTFILES_SYNC_INTERVAL
# seconds (default: 6h). Runs entirely in the background so shell startup is
# never blocked. Safe to source on every shell launch — the throttle check is
# a single zstat call before deciding whether to fork.
#
# Disable for a single shell:        DOTFILES_SYNC=0 zsh
# Override the interval globally:    export DOTFILES_SYNC_INTERVAL=3600
# Force a sync now (foreground):     dotfiles-sync
# =============================================================================

zmodload zsh/datetime
zmodload zsh/stat 2>/dev/null

() {
    emulate -L zsh
    [[ "${DOTFILES_SYNC:-1}" == "1" ]] || return 0

    local repo="${DOTFILES:-$HOME/.dotfiles}"
    [[ -d "$repo/.git" ]] || return 0

    local marker="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/last-pull"
    local interval=${DOTFILES_SYNC_INTERVAL:-21600}

    local last=0
    [[ -f "$marker" ]] && zstat -A last +mtime "$marker" 2>/dev/null
    (( EPOCHSECONDS - last < interval )) && return 0

    mkdir -p "${marker:h}"
    : > "$marker"   # touch first so concurrent shells don't all fork

    {
        cd "$repo" 2>/dev/null || exit 0
        git diff-index --quiet HEAD -- 2>/dev/null || exit 0
        git fetch --quiet 2>/dev/null || exit 0
        git merge --ff-only --quiet '@{u}' 2>/dev/null || exit 0
    } &!
}

# Foreground sync helper — for when you've just pushed and want it now.
dotfiles-sync() {
    emulate -L zsh
    local repo="${DOTFILES:-$HOME/.dotfiles}"
    [[ -d "$repo/.git" ]] || { print -u2 "no git repo at $repo"; return 1 }
    ( cd "$repo" && git pull --ff-only )
    : > "${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/last-pull"
}
