# =============================================================================
# Zinit — Zsh plugin manager (https://github.com/zdharma-continuum/zinit)
# =============================================================================

# Self-bootstrap: clone zinit if missing
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
    print -P "%F{33}▓▒░ %F{220}Installing Zinit (zdharma-continuum/zinit)…%f"
    command mkdir -p "$(dirname $ZINIT_HOME)"
    command git clone --depth=1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" \
        && print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" \
        || print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# -----------------------------------------------------------------------------
# Plugins — turbo mode (deferred until after first prompt)
# -----------------------------------------------------------------------------
zinit wait lucid for \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
        zdharma-continuum/fast-syntax-highlighting \
    atload"!_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    blockf atpull'zinit creinstall -q .' \
        zsh-users/zsh-completions

# Useful Oh-My-Zsh snippets (no OMZ install required)
zinit wait lucid for \
    OMZL::git.zsh \
    OMZP::git \
    OMZP::sudo \
    OMZP::command-not-found

# One Dark Pro–compatible muted suggestion grey (matches the comment colour)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5c6370'
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Keybindings
bindkey -e
bindkey '^[[A'   history-substring-search-up
bindkey '^[[B'   history-substring-search-down
bindkey '^ '     autosuggest-accept
