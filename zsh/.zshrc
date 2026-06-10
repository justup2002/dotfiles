# =============================================================================
# zsh/.zshrc — interactive shell config (~/.zshrc is a symlink to this file)
#
# Layout:
#   1. history + options
#   2. background dotfiles sync (throttled git pull)
#   3. aliases + local overrides
#   4. plugins — vendored in zsh/plugins/, loaded after first prompt
#   5. starship prompt (cached init)
#   6. background maintenance (zcompile)
# =============================================================================

# Self-locate when sourced directly; normally ~/.zshenv exported this already.
: "${DOTFILES:=${${(%):-%N}:A:h:h}}"
export DOTFILES

# Optional startup profiler: ZPROF=1 zsh -i -c exit
[[ -n "${ZPROF:-}" ]] && zmodload zsh/zprof

zmodload zsh/datetime
zmodload -F zsh/stat b:zstat 2>/dev/null

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
# Background dotfiles sync
#
# Pulls the repo from origin at most once per DOTFILES_SYNC_INTERVAL seconds
# (default 6h). The throttle check is one zstat call; the pull itself runs
# detached and never blocks startup. Plugins are vendored in-tree, so a pull
# updates them too — no separate plugin update step exists.
#
#   DOTFILES_SYNC=0              disable for this shell
#   DOTFILES_SYNC_INTERVAL=3600  override the interval (seconds)
#   dotfiles-sync                pull now, foreground
# -----------------------------------------------------------------------------
() {
    [[ "${DOTFILES_SYNC:-1}" == "1" ]] || return 0
    [[ -d "$DOTFILES/.git" ]] || return 0

    local marker="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/last-pull"
    local interval=${DOTFILES_SYNC_INTERVAL:-21600}

    local -a mt
    local last=0
    zstat -A mt +mtime "$marker" 2>/dev/null && last=$mt[1]
    (( EPOCHSECONDS - last < interval )) && return 0

    mkdir -p "${marker:h}"
    : > "$marker"   # touch first so concurrent shells don't all fork

    {
        cd "$DOTFILES" 2>/dev/null || exit 0
        git diff-index --quiet HEAD -- 2>/dev/null || exit 0
        git fetch --quiet 2>/dev/null || exit 0
        git merge --ff-only --quiet '@{u}' 2>/dev/null || exit 0
    } &!
}

dotfiles-sync() {
    [[ -d "$DOTFILES/.git" ]] || { print -u2 "no git repo at $DOTFILES"; return 1 }
    ( cd "$DOTFILES" && git pull --ff-only )
    : > "${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/last-pull"
}

# -----------------------------------------------------------------------------
# Aliases + local overrides (~/.zshrc.local is never tracked)
# -----------------------------------------------------------------------------
[[ -f "$DOTFILES/zsh/aliases.zsh" ]] && source "$DOTFILES/zsh/aliases.zsh"
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# -----------------------------------------------------------------------------
# Plugins — vendored at pinned commits under zsh/plugins/ (no plugin manager,
# no network). Loading is deferred via zsh-defer so the first prompt renders
# immediately; set DOTFILES_DEFER=0 to load synchronously (CI / debugging).
# -----------------------------------------------------------------------------
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5c6370'   # One Dark Pro comment grey
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_MANUAL_REBIND=1                # skip per-prompt rebind scan

# Default emacs keymap — safe to set before any plugin widget exists.
bindkey -e

_dotfiles_load_plugins() {
    local P="$DOTFILES/zsh/plugins"

    # Completions must be on fpath before compinit builds its dump.
    fpath+=("$P/zsh-completions/src")
    autoload -Uz compinit
    local dump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
    mkdir -p "${dump:h}"
    local -a mt
    local age=86401
    zstat -A mt +mtime "$dump" 2>/dev/null && (( age = EPOCHSECONDS - mt[1] ))
    if (( age < 86400 )); then
        compinit -C -d "$dump"   # reuse the dump, skip the audit
    else
        # -u: don't audit fpath ownership — the audit prompts (and aborts
        # without a tty, leaving compdef undefined) on runners/containers
        # where site-functions isn't root-owned. Same trust model as the
        # old zinit setup, which always ran compinit -C.
        compinit -u -d "$dump"   # full rebuild at most once a day
    fi

    source "$P/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
    source "$P/zsh-autosuggestions/zsh-autosuggestions.zsh"
    source "$P/zsh-history-substring-search/zsh-history-substring-search.zsh"
    source "$P/omz/lib/git.zsh"                                    # lib for the git plugin
    source "$P/omz/plugins/git/git.plugin.zsh"                     # git aliases (gst, gco, …)
    source "$P/omz/plugins/sudo/sudo.plugin.zsh"                   # Esc-Esc prepends sudo
    source "$P/omz/plugins/command-not-found/command-not-found.plugin.zsh"

    # Start autosuggestions after every other widget is registered so its
    # one-time bind (MANUAL_REBIND) wraps them all.
    _zsh_autosuggest_start
    bindkey '^ '   autosuggest-accept
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
}

if [[ "${DOTFILES_DEFER:-1}" == "1" ]]; then
    source "$DOTFILES/zsh/plugins/zsh-defer/zsh-defer.plugin.zsh"
    zsh-defer _dotfiles_load_plugins
else
    _dotfiles_load_plugins
fi

# -----------------------------------------------------------------------------
# Starship prompt — must be last
#
# `starship init zsh` output is cached so launches don't fork starship; the
# cache invalidates when the binary or starship.toml is newer than it.
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
# Background maintenance — byte-compile whatever is newer than its .zwc.
# Benefits the *next* shell, never blocks this one.
# -----------------------------------------------------------------------------
() {
    local -a files
    local f P="$DOTFILES/zsh/plugins"
    files=(
        "$HOME/.zshrc" "$HOME/.zshenv"
        "$DOTFILES"/zsh/*.zsh(N)
        "$P"/zsh-defer/zsh-defer.plugin.zsh
        "$P"/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
        "$P"/fast-syntax-highlighting/fast-highlight
        "$P"/fast-syntax-highlighting/fast-string-highlight
        "$P"/zsh-autosuggestions/zsh-autosuggestions.zsh
        "$P"/zsh-history-substring-search/zsh-history-substring-search.zsh
        "$P"/omz/lib/git.zsh
        "$P"/omz/plugins/*/*.plugin.zsh(N)
    )
    for f in $files; do
        [[ -s "$f" && (! -s "$f.zwc" || "$f" -nt "$f.zwc") ]] || continue
        zcompile -R -- "$f.zwc" "$f" 2>/dev/null
    done
} &!

[[ -n "${ZPROF:-}" ]] && zprof
