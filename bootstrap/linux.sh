#!/usr/bin/env bash
# =============================================================================
# bootstrap/linux.sh
# Idempotent installer for Ubuntu (Hyper-V VM), WSL2 Ubuntu, VS Code devcontainer
#
# Permission model:
#   - Root or passwordless sudo  → full install (apt, /usr/local/bin, chsh)
#   - No admin (NO_ADMIN=1, or sudo unavailable)
#       → installs everything under $HOME, skips apt + chsh + locale-gen.
#       → requires zsh, git, curl to already be on PATH; warns if not.
# =============================================================================
set -euo pipefail

log()  { printf '\033[1;34m▶\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# -----------------------------------------------------------------------------
# Permission detection
# -----------------------------------------------------------------------------
NO_ADMIN="${NO_ADMIN:-0}"
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""; HAVE_ADMIN=1
elif [ "$NO_ADMIN" = "1" ]; then
    SUDO=""; HAVE_ADMIN=0
elif have sudo; then
    SUDO="sudo"; HAVE_ADMIN=1
else
    SUDO=""; HAVE_ADMIN=0
fi

if [ "$HAVE_ADMIN" -eq 1 ]; then
    log "Admin mode (privileged installs available)."
else
    log "User-only mode — no admin privileges; installing under \$HOME."
fi

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ -f "$REPO_DIR/zsh/.zshrc" ] && [ "$REPO_DIR" != "$DOTFILES" ]; then
    if [ ! -e "$DOTFILES" ]; then
        log "Linking $REPO_DIR → $DOTFILES"
        ln -s "$REPO_DIR" "$DOTFILES"
    fi
fi
[ -d "$DOTFILES" ] || { err "DOTFILES not found at $DOTFILES"; exit 1; }
log "Using DOTFILES = $DOTFILES"

ENV_TAG="linux"
if grep -qi microsoft /proc/version 2>/dev/null; then ENV_TAG="wsl2"; fi
if [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${CODESPACES:-}" ]; then
    ENV_TAG="devcontainer"
fi
log "Environment: $ENV_TAG"

# -----------------------------------------------------------------------------
# System packages — only with admin
# -----------------------------------------------------------------------------
if [ "$HAVE_ADMIN" -eq 1 ] && have apt-get; then
    log "Installing system packages…"
    export DEBIAN_FRONTEND=noninteractive
    $SUDO apt-get update -qq
    $SUDO apt-get install -y --no-install-recommends \
        zsh git curl ca-certificates locales fontconfig
    if ! locale -a 2>/dev/null | grep -qi 'en_US.utf8'; then
        $SUDO locale-gen en_US.UTF-8 >/dev/null
    fi
    ok "Packages installed."
elif have apt-get; then
    warn "Skipping apt install (no admin). zsh/git/curl must already be present."
fi

MISSING=""
for cmd in zsh git curl; do
    have "$cmd" || MISSING="$MISSING $cmd"
done
if [ -n "$MISSING" ]; then
    err "Missing required tools:$MISSING"
    err "Install via your package manager and re-run this script."
    exit 1
fi

# -----------------------------------------------------------------------------
# Starship — /usr/local/bin with admin, ~/.local/bin without
# -----------------------------------------------------------------------------
if have starship; then
    ok "Starship already installed ($(starship --version | head -n1))."
elif [ "$HAVE_ADMIN" -eq 1 ]; then
    log "Installing Starship to /usr/local/bin…"
    curl -sS https://starship.rs/install.sh | $SUDO sh -s -- -y -b /usr/local/bin
    ok "Starship installed."
else
    log "Installing Starship to \$HOME/.local/bin…"
    mkdir -p "$HOME/.local/bin"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) warn "Add \$HOME/.local/bin to PATH (zsh/exports.zsh handles this for new shells)." ;;
    esac
    ok "Starship installed (user-only)."
fi

# -----------------------------------------------------------------------------
# Wire ~/.zshrc and ~/.zshenv
# -----------------------------------------------------------------------------
log "Linking ~/.zshrc → $DOTFILES/zsh/.zshrc"
if [ -e "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d-%H%M%S)"
    warn "Existing ~/.zshrc — backing up to $BACKUP"
    mv "$HOME/.zshrc" "$BACKUP"
fi
ln -sfn "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"

if ! grep -q 'DOTFILES=' "$HOME/.zshenv" 2>/dev/null; then
    echo "export DOTFILES=\"$DOTFILES\"" >> "$HOME/.zshenv"
fi
# Source the dotfiles-managed zshenv so env vars (e.g. SSH_AUTH_SOCK) are
# available in non-interactive zsh too — scripts, cron, `zsh -c …`.
if ! grep -q 'zshenv.zsh' "$HOME/.zshenv" 2>/dev/null; then
    echo '[ -r "$DOTFILES/zsh/zshenv.zsh" ] && source "$DOTFILES/zsh/zshenv.zsh"' >> "$HOME/.zshenv"
fi
ok "Zsh config linked."

# -----------------------------------------------------------------------------
# Default shell — chsh with admin, ~/.bashrc shim without
# -----------------------------------------------------------------------------
if [ "$ENV_TAG" = "devcontainer" ]; then
    log "Devcontainer detected — skipping default-shell setup."
elif [ "$HAVE_ADMIN" -eq 1 ]; then
    ZSH_BIN="$(command -v zsh)"
    CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7 || echo "$SHELL")"
    if [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
        log "Setting default shell to $ZSH_BIN…"
        if ! grep -qx "$ZSH_BIN" /etc/shells 2>/dev/null; then
            echo "$ZSH_BIN" | $SUDO tee -a /etc/shells >/dev/null
        fi
        # Run chsh via sudo so PAM doesn't prompt for the user's password
        # (root doesn't need to authenticate to chsh). Falls back to usermod
        # if chsh is unavailable.
        if $SUDO chsh -s "$ZSH_BIN" "$USER" 2>/dev/null \
            || $SUDO usermod -s "$ZSH_BIN" "$USER" 2>/dev/null; then
            ok "Default shell changed (effective on next login)."
        else
            warn "Could not change default shell — falling back to ~/.bashrc shim."
            HAVE_ADMIN=0   # trigger shim block below
        fi
    else
        ok "zsh already the default shell."
    fi
fi

if [ "$HAVE_ADMIN" -eq 0 ] && [ "$ENV_TAG" != "devcontainer" ]; then
    SHIM_MARK="# dotfiles: launch zsh on login"
    if [ -f "$HOME/.bashrc" ] && ! grep -qF "$SHIM_MARK" "$HOME/.bashrc"; then
        cat >> "$HOME/.bashrc" <<EOF

$SHIM_MARK
if [[ \$- == *i* ]] && command -v zsh >/dev/null && [ -z "\$ZSH_VERSION" ]; then
    exec zsh
fi
EOF
        ok "Added 'exec zsh' shim to ~/.bashrc (no-admin default-shell fallback)."
    fi
fi

# -----------------------------------------------------------------------------
# Zinit + plugins (cloned to ~/.local/share/zinit, no admin needed)
# -----------------------------------------------------------------------------
log "Bootstrapping Zinit…"
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
TIMEOUT_BIN=""
have timeout && TIMEOUT_BIN="timeout 60"

if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname "$ZINIT_HOME")"
    for attempt in 1 2 3; do
        if $TIMEOUT_BIN git clone --depth=1 \
                https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" \
                </dev/null >/dev/null 2>&1; then
            ok "Zinit cloned."
            break
        fi
        rm -rf "$ZINIT_HOME"
        warn "Zinit clone failed (attempt ${attempt}/3) — retrying…"
        sleep 2
    done
    [ -d "$ZINIT_HOME/.git" ] \
        || warn "Zinit clone did not succeed — first interactive launch will retry."
fi

if [ -r "$ZINIT_HOME/zinit.zsh" ]; then
    # `timeout` is a belt-and-braces guard in case git ever prompts.
    if $TIMEOUT_BIN zsh -df -c \
        'source "'"$ZINIT_HOME"'/zinit.zsh"; zinit self-update' \
        </dev/null >/dev/null 2>&1; then
        ok "Zinit ready."
    else
        warn "Zinit self-update returned non-zero — will retry on first interactive launch."
    fi
else
    warn "Zinit not found at $ZINIT_HOME — will install on first interactive launch."
fi

# -----------------------------------------------------------------------------
# Pre-load plugins + snippets via zinit itself, so the plugin list stays in
# one place (zsh/zinit.zsh). We source the dotfiles' zinit config in a
# non-interactive zsh and force zinit to flush its turbo queue with
# `@zinit-scheduler burst` — that performs the same clones + snippet
# downloads the first interactive shell would, but at bootstrap time.
#
# Retried up to 3 times to tolerate transient GitHub clone failures.
# -----------------------------------------------------------------------------
if [ -r "$ZINIT_HOME/zinit.zsh" ] && [ -r "$DOTFILES/zsh/zinit.zsh" ]; then
    log "Pre-loading Zinit plugins + snippets…"
    PRELOAD_OK=0
    for attempt in 1 2 3 4 5; do
        # `zsh -df` skips user rc files; we explicitly source zinit + the
        # dotfiles' zinit config, then burst the scheduler. Errors from
        # missing widgets / interactive-only features are expected and
        # silenced — we only care that the network installs succeed.
        if $TIMEOUT_BIN zsh -df +o promptsubst -c '
            export DOTFILES="'"$DOTFILES"'"
            source "'"$ZINIT_HOME"'/zinit.zsh" 2>/dev/null
            source "$DOTFILES/zsh/zinit.zsh" 2>/dev/null

            # Snapshot the pending turbo queue BEFORE bursting it. Each task
            # row looks like: "<ts>+<delay>+<run> <p|s> <id> <a> <name>".
            # type=p → plugin (user/repo), type=s → snippet (e.g. OMZP::git).
            local -a expected_plugins expected_snippets
            local task type name
            for task in "${ZINIT_TASKS[@]}"; do
                [[ "$task" == "<no-data>" ]] && continue
                # Fields: 1=ts+..., 2=type, 3=id, 4=a, 5=name
                type="${${(z)task}[2]}"
                name="${${(z)task}[5]}"
                case "$type" in
                    p) expected_plugins+=("$name") ;;
                    s) expected_snippets+=("$name") ;;
                esac
            done

            # Force all `zinit wait...` units to install/load now.
            @zinit-scheduler burst 2>/dev/null

            # Verify each expected plugin has a clone on disk.
            local entry dir
            for entry in "${expected_plugins[@]}"; do
                dir="${ZINIT[PLUGINS_DIR]}/${entry//\//---}"
                [[ -d "$dir/.git" ]] || exit 1
            done
            # Verify each expected snippet was downloaded. Zinit creates a
            # dir under SNIPPETS_DIR named exactly after the identifier.
            for entry in "${expected_snippets[@]}"; do
                [[ -d "${ZINIT[SNIPPETS_DIR]}/$entry" ]] || exit 1
            done
        ' </dev/null >/dev/null 2>&1; then
            PRELOAD_OK=1
            break
        fi
        warn "Pre-load attempt ${attempt}/5 failed — retrying…"
        sleep $(( attempt * 3 ))
    done
    if [ "$PRELOAD_OK" -eq 1 ]; then
        ok "Plugins + snippets cached."
    else
        warn "Pre-load did not fully succeed — first interactive launch will retry."
    fi
else
    warn "Skipping plugin pre-load (zinit or dotfiles config not readable)."
fi

ok "Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Open a new terminal (or run: exec zsh)"
echo "  2. First launch installs plugins — give it ~5s on the initial prompt."
echo "  3. Set your terminal font to 'MesloLGS NF' (see fonts/README.md)."
echo "  4. Updates from GitHub apply automatically (≤ 6h lag); force one with: dotfiles-sync"
