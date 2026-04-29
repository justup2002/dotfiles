# =============================================================================
# zsh/zshenv.zsh — env vars for ALL zsh contexts
#
# Sourced from ~/.zshenv (after $DOTFILES is set), so values here are visible
# to interactive shells, non-interactive `zsh -c` calls, scripts, and cron —
# anywhere `.zshrc` would be skipped. Keep this file limited to env vars that
# external tools (git, ssh, editors) need; interactive-only setup belongs in
# .zshrc / exports.zsh.
# =============================================================================

# 1Password SSH agent. Only export when the socket exists, so a plain Linux
# VM or devcontainer without 1Password falls back to the default ssh-agent
# instead of pointing at a dead path.
if [[ -S "$HOME/.ssh/1password-agent.sock" ]]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/1password-agent.sock"
fi
