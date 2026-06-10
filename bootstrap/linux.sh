#!/usr/bin/env bash
# =============================================================================
# bootstrap/linux.sh — WSL2 Ubuntu, Linux VMs, VS Code devcontainers
#
# User-scope by default; idempotent; safe to re-run. Phases (mirrored by
# bootstrap/windows.ps1):
#
#   1. detect   — environment (wsl2 / devcontainer / linux)
#   2. tools    — starship → ~/.local/bin (sudo is used only if zsh itself
#                 is missing, and only when it can work: tty or NOPASSWD)
#   3. link     — ~/.zshenv + ~/.zshrc symlinks into the repo (backup first)
#   4. shell    — make zsh the login shell (chsh if free, ~/.bashrc shim else)
#
# Plugins are vendored in zsh/plugins/ and arrive with the clone — there is
# no plugin manager, no extra network fetch, and nothing to retry.
# =============================================================================
set -euo pipefail

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(cd "$SCRIPT_DIR/.." && pwd)"
[ -f "$DOTFILES/zsh/.zshrc" ] || { err "Repo not found around $SCRIPT_DIR"; exit 1; }
log "Using DOTFILES = $DOTFILES"

# -----------------------------------------------------------------------------
# 1. detect
# -----------------------------------------------------------------------------
ENV_TAG="linux"
if grep -qi microsoft /proc/version 2>/dev/null; then ENV_TAG="wsl2"; fi
if [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${CODESPACES:-}" ]; then
    ENV_TAG="devcontainer"
fi
log "Environment: $ENV_TAG"

# sudo we can actually use without hanging a non-interactive bootstrap:
# we're root, sudo is passwordless, or there's a tty to type a password on.
SUDO=""
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
elif have sudo && { sudo -n true 2>/dev/null || [ -t 0 ]; }; then
    SUDO="sudo"
fi

# -----------------------------------------------------------------------------
# 2. tools
# -----------------------------------------------------------------------------
if ! have zsh; then
    if { [ "$(id -u)" -eq 0 ] || [ -n "$SUDO" ]; } && have apt-get; then
        log "Installing zsh (the only package this bootstrap ever installs)…"
        export DEBIAN_FRONTEND=noninteractive
        $SUDO apt-get update -qq
        $SUDO apt-get install -y --no-install-recommends zsh
        ok "zsh installed."
    else
        err "zsh is required and not installed (no usable sudo to install it)."
        err "Install it (e.g. 'apt-get install zsh') and re-run."
        exit 1
    fi
fi

for cmd in git curl; do
    have "$cmd" || { err "$cmd is required but missing."; exit 1; }
done

if have starship || [ -x "$HOME/.local/bin/starship" ]; then
    ok "Starship already installed."
else
    log "Installing Starship to ~/.local/bin (user scope)…"
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin" >/dev/null
    ok "Starship installed."
fi

# -----------------------------------------------------------------------------
# 3. link — the only files this bootstrap touches in $HOME
# -----------------------------------------------------------------------------
link_into_home() {
    src=$1 dst=$2
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        backup="$dst.backup.$(date +%Y%m%d-%H%M%S)"
        warn "Existing $dst — backing up to $backup"
        mv "$dst" "$backup"
    fi
    ln -sfn "$src" "$dst"
    ok "Linked $dst → $src"
}
link_into_home "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv"
link_into_home "$DOTFILES/zsh/.zshrc"  "$HOME/.zshrc"

# -----------------------------------------------------------------------------
# 4. shell
# -----------------------------------------------------------------------------
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || true)"

if [ "$ENV_TAG" = "devcontainer" ]; then
    log "Devcontainer — default shell comes from the image / VS Code settings."
elif [ "$CURRENT_SHELL" = "$ZSH_BIN" ]; then
    ok "zsh already the default shell."
elif [ -n "$SUDO" ] || [ "$(id -u)" -eq 0 ]; then
    if ! grep -qx "$ZSH_BIN" /etc/shells 2>/dev/null; then
        echo "$ZSH_BIN" | $SUDO tee -a /etc/shells >/dev/null
    fi
    if $SUDO chsh -s "$ZSH_BIN" "$USER" 2>/dev/null \
        || $SUDO usermod -s "$ZSH_BIN" "$USER" 2>/dev/null; then
        ok "Default shell set to zsh (effective on next login)."
    else
        warn "chsh failed — falling back to the ~/.bashrc shim."
        SUDO=""
    fi
fi

if [ "$ENV_TAG" != "devcontainer" ] && [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ] \
    && [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
    SHIM_MARK="# dotfiles: launch zsh on login"
    if ! grep -qF "$SHIM_MARK" "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<EOF

$SHIM_MARK
if [[ \$- == *i* ]] && command -v zsh >/dev/null && [ -z "\$ZSH_VERSION" ]; then
    exec zsh
fi
EOF
        ok "Added 'exec zsh' shim to ~/.bashrc (no sudo needed)."
    fi
fi

ok "Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Open a new terminal (or run: exec zsh) — plugins are already local."
echo "  2. Set your terminal font to 'MesloLGS NF' (installed by the Windows bootstrap)."
echo "  3. Updates apply automatically (≤ 6h lag); force one with: dotfiles-sync"
