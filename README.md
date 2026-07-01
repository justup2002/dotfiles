# dotfiles

Unified shell experience across Windows, WSL2, Linux VMs, and dev containers —
designed around three rules:

1. **No admin required.** Everything installs to user scope. The only thing
   that ever wants sudo is `apt-get install zsh`, and only when zsh is missing.
2. **No network at shell startup, (almost) none at bootstrap.** Zsh plugins are
   vendored into this repo at pinned commits — `git clone` *is* the plugin
   install. Bootstrap's only download is the starship binary.
3. **One mental model on every OS.** `bootstrap/linux.sh` and
   `bootstrap/windows.ps1` run the same phases: detect → tools → link → shell.

| Component        | Choice                                                  |
| ---------------- | ------------------------------------------------------- |
| Prompt           | [Starship](https://starship.rs) (+ Claude Code statusline) |
| Shell (Linux)    | Zsh                                                     |
| Shell (Windows)  | PowerShell 7                                            |
| Plugins          | vendored at pinned commits in `zsh/plugins/` — `fast-syntax-highlighting`, `zsh-autosuggestions`, `zsh-history-substring-search`, `zsh-completions`, OMZ `git`/`sudo`/`command-not-found`, loaded via `zsh-defer` |
| Nerd Font        | MesloLGS NF                                             |
| Theme            | One Dark Pro                                            |

## Quick start

### Inside WSL2 Ubuntu / Linux VM / dev container
```bash
git clone https://github.com/justup2002/dotfiles.git ~/.dotfiles
~/.dotfiles/bootstrap/linux.sh
exec zsh
```
The clone can live anywhere — configs self-locate. The bootstrap only:
installs starship to `~/.local/bin`, symlinks `~/.zshenv` + `~/.zshrc`
(backing up existing files), and sets the login shell (`chsh` when it's free,
otherwise a `~/.bashrc` shim — no password prompts, no surprises).

### Windows host (PowerShell, no admin)
```powershell
git clone https://github.com/justup2002/dotfiles.git $HOME\.dotfiles
& $HOME\.dotfiles\bootstrap\windows.ps1
```
Then in Windows Terminal: **Settings → Defaults → Appearance** → set
**Color scheme** = `One Dark Pro`, **Font face** = `MesloLGS NF`.

### VS Code dev containers — set once, applies everywhere
```json
{
    "dotfiles.repository":     "justup2002/dotfiles",
    "dotfiles.installCommand": "bootstrap/linux.sh"
}
```

### VS Code itself
`code --install-extension zhuangtongfa.material-theme`, then merge
`vscode/settings.json` into your User settings.

## How plugins work (and why there's no plugin manager)

Plugin managers re-download plugins per machine — over the network, at
bootstrap or first launch, with all the flakiness that implies (made worse by
git `insteadOf` rewrites that silently turn anonymous HTTPS clones into SSH).
Instead, plugins live in `zsh/plugins/` at pinned commits and ride along with
the repo clone. Every environment gets byte-identical plugins, instantly, and
the regular dotfiles sync updates them like any other file.

- **Update/bump plugins:** edit the SHAs in `tools/update-plugins.sh`, run it
  (uses curl + codeload tarballs, immune to git URL rewrites), review the
  diff, commit. Each plugin dir has a `.pin` recording its source.
- **Startup cost:** plugins load after the first prompt via
  [`zsh-defer`](https://github.com/romkatv/zsh-defer) (also vendored).
  `DOTFILES_DEFER=0` forces synchronous loading (CI, debugging).

## Updating

New shells pull the repo from origin in the background, at most once per 6h —
a single `zstat` check, never blocking startup. The same logic exists in both
`zsh/.zshrc` and `powershell/profile.ps1`:

- `DOTFILES_SYNC=0` — disable for this shell.
- `DOTFILES_SYNC_INTERVAL=3600` — seconds between pulls (default 21600).
- `dotfiles-sync` — pull now, foreground.

Auto-sync skips if the tree is dirty, there's no upstream, or the merge isn't
fast-forward.

## Startup speed

- **Plugins deferred** until after the first prompt (`zsh-defer`).
- **compinit**: cached dump with the security scan at most once per day.
- **Starship init cached** to `$XDG_CACHE_HOME/starship/init.zsh` (and
  `%LOCALAPPDATA%\starship\init.ps1` on Windows) — invalidated when the binary
  or `starship.toml` changes. Saves a fork per shell.
- **zcompile**: configs and plugin entry files are byte-compiled in the
  background after launch; later shells skip the parse.

Profile a launch: `ZPROF=1 zsh -i -c exit` /
`$env:PSPROFILE='1'; pwsh -NoLogo -Command exit`.

## Permissions

| Action | Scope |
| --- | --- |
| starship | `~/.local/bin` (Linux) / winget `--scope user` (Windows) |
| plugins | already in the repo — nothing to install |
| configs | two symlinks in `$HOME` (Linux) / a source line in `$PROFILE` (Windows) |
| fonts | `%LOCALAPPDATA%\...\Fonts` per-user (Windows); Linux terminals render with the host's font |
| login shell | `chsh` only when root/passwordless-sudo; else `~/.bashrc` shim |
| locale | uses `C.UTF-8` fallback — no `locale-gen` |
| `apt-get install zsh` | the one sudo action, only if zsh is missing |

## Claude Code statusline

`starship/claude-code-statusline.sh` turns Claude Code's status JSON into a
starship-rendered powerline (model + effort, context gauge, session cost and
lines added/removed, 5h/7d limits). Wire it up in `~/.claude/settings.json`:

```json
{ "statusLine": { "command": "~/.dotfiles/starship/claude-code-statusline.sh" } }
```

The statusline's starship profile lives in `starship/starship.toml`
(`[profiles] claude-code`).

## 1Password SSH agent (WSL2 → Windows)

`zsh/.zshenv` exports `SSH_AUTH_SOCK=~/.ssh/1password-agent.sock` **only when
that socket exists**, so:

- **WSL2**: point your relay (npiperelay/wsl2-ssh-agent unit) at that path and
  every shell uses the Windows 1Password agent.
- **Dev containers / VMs**: the socket doesn't exist, so the environment's own
  agent (e.g. the one VS Code forwards from the host) is left untouched.

## Customisation

- Aliases: `zsh/aliases.zsh` (committed) or `~/.zshrc.local` (local-only).
- Prompt: `starship/starship.toml` — both shells re-read it on change.
- PowerShell extras: `~/Documents/PowerShell/profile.local.ps1`, auto-sourced.
- Add a plugin: add a `vendor` line in `tools/update-plugins.sh`, run it, and
  source the new file in `_dotfiles_load_plugins` (`zsh/.zshrc`).

## Migrating from the zinit version

Re-run `bootstrap/linux.sh` (it replaces `~/.zshrc`/`~/.zshenv` with symlinks,
backing up the old files) and optionally clean up: `rm -rf ~/.local/share/zinit`.
On Windows, re-run `bootstrap/windows.ps1`.

## Uninstalling

- Linux: delete the `~/.zshrc` / `~/.zshenv` symlinks (restore any
  `*.backup.*`), remove `~/.dotfiles`.
- Windows: remove the source line from `$PROFILE`, delete
  `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles-onedarkpro\`.

MIT licensed. Vendored plugins keep their upstream licenses (see
`zsh/plugins/*/LICENSE*` and `.pin` files).
