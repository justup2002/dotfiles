# dotfiles

Unified shell experience across Windows, WSL2, Linux VMs, and dev containers.

| Component        | Choice                                         |
| ---------------- | ---------------------------------------------- |
| Prompt           | [Starship](https://starship.rs)                |
| Shell (Linux)    | Zsh                                            |
| Shell (Windows)  | PowerShell 7                                   |
| Plugin manager   | [Zinit](https://github.com/zdharma-continuum/zinit) (turbo mode) |
| Plugins          | `fast-syntax-highlighting`, `zsh-autosuggestions`, `zsh-completions` |
| Nerd Font        | MesloLGS NF                                    |
| Theme            | One Dark Pro                                   |

Targets covered:

- ✅ Windows Terminal → WSL2 Ubuntu
- ✅ Windows Terminal → PowerShell (5.1 and 7)
- ✅ VS Code → integrated terminal (Windows + Linux + WSL Remote)
- ✅ VS Code → Dev Container
- ✅ SSH to Hyper-V Ubuntu VM (from any Nerd-Font-capable client)

## Quick start

### Windows host (PowerShell, admin not required)
```powershell
git clone https://github.com/<your-username>/dotfiles.git $HOME\.dotfiles
cd $HOME\.dotfiles
.\bootstrap\windows.ps1
```
Then in Windows Terminal: **Settings → Defaults → Appearance** → set
**Color scheme** = `One Dark Pro`, **Font face** = `MesloLGS NF`.

### Inside WSL2 Ubuntu / Hyper-V VM / dev container
```bash
git clone https://github.com/<your-username>/dotfiles.git ~/.dotfiles
~/.dotfiles/bootstrap/linux.sh
exec zsh
```

### VS Code dev containers — set once, applies everywhere
In VS Code **User Settings (JSON)**:
```json
{
    "dotfiles.repository":     "<your-username>/dotfiles",
    "dotfiles.installCommand": "bootstrap/linux.sh",
    "dotfiles.targetPath":     "~/.dotfiles"
}
```

### VS Code itself
```
code --install-extension zhuangtongfa.material-theme
```
Then merge `vscode/settings.json` into your User settings JSON.

## Customisation

- Aliases / functions: edit `zsh/aliases.zsh` (committed) or `~/.zshrc.local` (local-only).
- Prompt: edit `starship/starship.toml`. Both shells re-read it on launch.
- PowerShell extras: drop machine-specific tweaks into
  `~/Documents/PowerShell/profile.local.ps1` — auto-sourced if present.
- Add a plugin: in `zsh/zinit.zsh` add a line under the `zinit wait lucid for` block.

## Updating

New zsh shells auto-pull the dotfiles repo from `origin` in the background, at
most once per 6 hours. The check is a single `zstat` call — it does not block
shell startup, and the `git fetch` itself runs detached (`&!`). Subsequent
shells pick up the new config automatically; the running shell can be reloaded
with `reload` (alias for `exec zsh`).

Tunables (set in `~/.zshrc.local` or per-shell):
- `DOTFILES_SYNC=0` — disable auto-sync for this shell.
- `DOTFILES_SYNC_INTERVAL=3600` — seconds between pulls (default 21600 = 6h).
- `dotfiles-sync` — function that pulls now, foreground, useful right after a push.

Auto-sync is intentionally conservative: it skips the pull if the working tree
is dirty, if there's no upstream branch, or if the merge isn't fast-forward.

PowerShell behaves the same — `$PROFILE` performs the throttled background
pull on every load via `Invoke-DotfilesSync` (uses `Start-ThreadJob` on PS7+,
falls back to `Start-Job` on Windows PowerShell 5.1). Same env knobs:
`$env:DOTFILES_SYNC=0` to disable, `$env:DOTFILES_SYNC_INTERVAL=3600` to
override, `dotfiles-sync` to pull foreground.

## Startup speed

### Zsh
- **Plugin defer**: `zinit wait lucid` loads `fast-syntax-highlighting`,
  autosuggestions, and completions *after* the first prompt renders.
- **Compinit cache**: zinit's `zicompinit` reuses `.zcompdump` across launches.
- **Starship init cache**: `starship init zsh --print-full-init` is cached to
  `$XDG_CACHE_HOME/starship/init.zsh` and invalidated only when the starship
  binary or `starship.toml` changes — saves a fork+exec per shell.
- **zcompile**: `~/.zshrc` and the modules under `zsh/` are byte-compiled to
  `.zwc` in the background after first launch; subsequent shells skip the
  parse step.

Profile a launch: `ZPROF=1 zsh -i -c exit`

### PowerShell
- **Starship init cache**: same trick as zsh — `starship init powershell
  --print-full-init` is cached to `%LOCALAPPDATA%\starship\init.ps1` and
  dot-sourced; saves a starship subprocess per shell.
- **Lazy module imports**: `try { Import-Module X }` in place of
  `Get-Module -ListAvailable -Name X`, which scans every module path on disk
  (~200–500ms on Windows). Modules either import or silently skip.
- **PSReadLine prediction view**: `InlineView` is the fastest of the prediction
  styles; ListView is prettier but redraws on every keystroke.

Profile a launch: `$env:PSPROFILE='1'; pwsh -NoLogo -Command exit`

## No-admin mode

The bootstrap auto-detects whether it can elevate (root, or `sudo` on PATH).
Force user-only with `NO_ADMIN=1 ./bootstrap/linux.sh`.

In user-only mode the Linux script:
- Skips `apt install` (zsh, git, curl must already be present).
- Installs Starship to `~/.local/bin` instead of `/usr/local/bin`.
- Skips `chsh` and instead appends an `exec zsh` shim to `~/.bashrc`.
- Skips `locale-gen` and `/etc/shells` edits.

The Windows bootstrap is already user-scoped: `winget install --scope user`,
`Install-Module -Scope CurrentUser`, fonts in `%LOCALAPPDATA%\Microsoft\Windows\Fonts`,
WT fragment in `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\`. UAC will
only appear if a winget package can't be satisfied in user scope.

### Things you cannot do without admin

| Capability | Needs admin? | User-only fallback |
| --- | --- | --- |
| `apt install zsh git curl` | yes | tools must be pre-installed (most distros + Codespaces ship them) |
| `chsh -s /usr/bin/zsh` (true default shell) | yes | `~/.bashrc` shim re-execs zsh on interactive bash launch — costs ~5–20ms and a stray bash process |
| Add `/usr/bin/zsh` to `/etc/shells` | yes | not needed if you're using the bashrc shim |
| `locale-gen en_US.UTF-8` | yes | rely on `C.UTF-8` (almost always pre-built); some glyph rendering may differ |
| Install fonts system-wide | yes (Linux: `/usr/share/fonts`) | per-user dir works on Linux (`~/.local/share/fonts`) and Windows (`%LOCALAPPDATA%\Microsoft\Windows\Fonts`) — both already used by `fonts/install-meslo-linux.sh` and `bootstrap/windows.ps1` |
| Write to `/usr/local/bin` (Starship) | yes | `~/.local/bin` works; ensure it's on PATH (`exports.zsh` handles new shells) |
| Install system-wide CA bundles, codepages, services | yes | none — these are genuinely root-only |

Everything else (Zinit, plugins, prompt, theme, history, completions) lives
under `$HOME` and works identically in either mode.

## Uninstalling

- Delete `~/.zshrc` (or restore `.zshrc.backup.<timestamp>` left by the bootstrap).
- Remove `~/.dotfiles`.
- Remove the source line from `$PROFILE`.
- Delete `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles-onedarkpro\`.

MIT licensed.
