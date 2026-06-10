#!/usr/bin/env bash
# =============================================================================
# tools/update-plugins.sh — (re)vendor the pinned zsh plugins into zsh/plugins/
#
# The dotfiles deliberately have no runtime plugin manager: plugins are
# committed to this repo at pinned commits, so bootstrapping an environment
# never performs a plugin download (and can never flake on one). This script
# is the only thing that talks to the network for plugins — run it on a dev
# machine to bump the pins below, review the diff, and commit.
#
# Downloads use codeload tarballs over plain HTTPS via curl, so they are not
# affected by git url.insteadOf rewrites (which can silently turn anonymous
# https clones into SSH and fail in agent-less environments).
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGINS_DIR="$REPO_ROOT/zsh/plugins"

# ----------------------------------------------------------------------------
# Pins — bump the SHAs, re-run, review `git diff`, commit.
# ----------------------------------------------------------------------------
FSH_SHA=3d574ccf48804b10dca52625df13da5edae7f553         # zdharma-continuum/fast-syntax-highlighting master
AUTOSUGGEST_SHA=85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5 # zsh-users/zsh-autosuggestions master (v0.7.1+)
HSS_SHA=14c8d2e0ffaee98f2df9850b19944f32546fdea5         # zsh-users/zsh-history-substring-search master
COMPLETIONS_SHA=dd83145816fe2d90b1ab4154ed528050e94ac5e3 # zsh-users/zsh-completions master
DEFER_SHA=53a26e287fbbe2dcebb3aa1801546c6de32416fa       # romkatv/zsh-defer master
OMZ_SHA=c954bbb168fc645592c50017de0d0e138db8df5f         # ohmyzsh/ohmyzsh master

# vendor <name> <owner/repo> <sha> <path-to-keep>...
# Downloads the repo tarball at <sha> and copies only the listed paths
# (files or directories, relative to the repo root) into zsh/plugins/<name>/,
# preserving their relative layout. Records provenance in .pin.
vendor() {
    local name=$1 repo=$2 sha=$3
    shift 3

    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    echo "▶ $name ← $repo@${sha:0:10}"
    curl -fsSL --retry 3 --retry-delay 2 \
        "https://codeload.github.com/$repo/tar.gz/$sha" |
        tar -xz -C "$tmp" --strip-components=1

    rm -rf "${PLUGINS_DIR:?}/$name"
    mkdir -p "$PLUGINS_DIR/$name"

    local path
    for path in "$@"; do
        [ -e "$tmp/$path" ] || { echo "✗ $repo@$sha is missing '$path'" >&2; exit 1; }
        (cd "$tmp" && cp -r --parents "$path" "$PLUGINS_DIR/$name/")
    done
    printf 'https://github.com/%s %s\n' "$repo" "$sha" > "$PLUGINS_DIR/$name/.pin"
}

mkdir -p "$PLUGINS_DIR"

vendor zsh-defer romkatv/zsh-defer "$DEFER_SHA" \
    zsh-defer zsh-defer.plugin.zsh LICENSE

vendor fast-syntax-highlighting zdharma-continuum/fast-syntax-highlighting "$FSH_SHA" \
    fast-syntax-highlighting.plugin.zsh \
    fast-highlight fast-string-highlight fast-theme _fast-theme \
    .fast-make-targets .fast-read-ini-file .fast-run-command \
    .fast-run-git-command .fast-zts-read-all \
    →chroma share themes LICENSE

vendor zsh-autosuggestions zsh-users/zsh-autosuggestions "$AUTOSUGGEST_SHA" \
    zsh-autosuggestions.zsh LICENSE

vendor zsh-history-substring-search zsh-users/zsh-history-substring-search "$HSS_SHA" \
    zsh-history-substring-search.zsh

vendor zsh-completions zsh-users/zsh-completions "$COMPLETIONS_SHA" \
    src LICENSE

vendor omz ohmyzsh/ohmyzsh "$OMZ_SHA" \
    lib/git.zsh \
    plugins/git/git.plugin.zsh \
    plugins/sudo/sudo.plugin.zsh \
    plugins/command-not-found/command-not-found.plugin.zsh \
    LICENSE.txt

echo
echo "✓ Vendored to $PLUGINS_DIR — review 'git diff' and commit."
