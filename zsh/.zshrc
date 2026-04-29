# =============================================================================
# ~/.zshrc — managed by dotfiles repo
# =============================================================================

# Resolve dotfiles location (set by bootstrap; default to ~/.dotfiles)
export DOTFILES="${DOTFILES:-$HOME/.dotfiles}"

# Optional startup profiler: ZPROF=1 zsh -i -c exit
[[ -n "${ZPROF:-}" ]] && zmodload zsh/zprof

# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt HIST_REDUCE_BLANKS
setopt EXTENDED_HISTORY

# -----------------------------------------------------------------------------
# Shell options
# -----------------------------------------------------------------------------
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS

# -----------------------------------------------------------------------------
# Source modular config
# -----------------------------------------------------------------------------
[ -f "$DOTFILES/zsh/exports.zsh" ] && source "$DOTFILES/zsh/exports.zsh"
[ -f "$DOTFILES/zsh/sync.zsh" ]    && source "$DOTFILES/zsh/sync.zsh"
[ -f "$DOTFILES/zsh/zinit.zsh" ]   && source "$DOTFILES/zsh/zinit.zsh"
[ -f "$DOTFILES/zsh/aliases.zsh" ] && source "$DOTFILES/zsh/aliases.zsh"

# Local overrides (not tracked in git)
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"

# -----------------------------------------------------------------------------
# Starship prompt — must be last
#
# Cache the output of `starship init zsh` so we don't fork starship on every
# shell launch. Cache invalidates when the starship binary or its config
# changes (mtime check).
# -----------------------------------------------------------------------------
_starship_bin=$(command -v starship)
if [[ -n "$_starship_bin" ]]; then
    export STARSHIP_CONFIG="$DOTFILES/starship/starship.toml"
    _starship_cache="${XDG_CACHE_HOME:-$HOME/.cache}/starship/init.zsh"
    if [[ ! -s "$_starship_cache" \
        || "$_starship_bin" -nt "$_starship_cache" \
        || "$STARSHIP_CONFIG" -nt "$_starship_cache" ]]; then
        mkdir -p "${_starship_cache:h}"
        "$_starship_bin" init zsh --print-full-init >| "$_starship_cache"
    fi
    source "$_starship_cache"
fi
unset _starship_bin _starship_cache

# -----------------------------------------------------------------------------
# Background maintenance — compile our zsh files when source is newer than
# its .zwc. Benefits the *next* shell, never blocks this one.
# -----------------------------------------------------------------------------
{
    local f
    for f in "$HOME/.zshrc" "$DOTFILES"/zsh/*.zsh; do
        [[ -s "$f" && (! -s "$f.zwc" || "$f" -nt "$f.zwc") ]] || continue
        zcompile -R -- "$f.zwc" "$f" 2>/dev/null
    done
} &!

[[ -n "${ZPROF:-}" ]] && zprof
