# =============================================================================
# zsh/.zshenv — environment for ALL zsh contexts (interactive, scripts, cron)
#
# ~/.zshenv is a symlink to this file. DOTFILES is derived from the symlink
# target, so no path is hardcoded and nothing is ever appended to home files.
# Keep this file limited to env vars that external tools (git, ssh, editors)
# need; interactive-only setup belongs in .zshrc.
# =============================================================================

export DOTFILES="${${(%):-%N}:A:h:h}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# User-scope binaries (the bootstrap installs starship here).
typeset -U path PATH
path=("$HOME/.local/bin" $path)
export PATH

export EDITOR="${EDITOR:-nano}"
export VISUAL="$EDITOR"

# C.UTF-8 ships with glibc — works everywhere without locale-gen (or sudo).
export LANG="${LANG:-C.UTF-8}"

export PAGER='less'
export LESS='-R --use-color -Dd+r$Du+b'

# 1Password SSH agent (WSL2 relay socket). Only exported when the socket
# exists, so devcontainers and VMs keep their own agent — e.g. the socket
# VS Code forwards from the host, which is how 1Password reaches containers.
if [[ -S "$HOME/.ssh/1password-agent.sock" ]]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/1password-agent.sock"
fi
