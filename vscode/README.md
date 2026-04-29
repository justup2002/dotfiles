# VS Code — One Dark Pro + MesloLGS NF

## 1. Install One Dark Pro theme
```
code --install-extension zhuangtongfa.material-theme
```
## 2. Merge `settings.json` into User settings
`Ctrl/Cmd+Shift+P` → **Preferences: Open User Settings (JSON)** → merge keys
from `vscode/settings.json` in this repo.

## 3. Behaviour by environment

| Environment            | Theme        | Terminal shell                              | Font        |
| ---------------------- | ------------ | ------------------------------------------- | ----------- |
| Local Windows VS Code  | One Dark Pro | PowerShell (or pwsh / WSL)                  | MesloLGS NF |
| Local Linux VS Code    | One Dark Pro | zsh + Starship + zinit                      | MesloLGS NF |
| WSL2 Remote            | One Dark Pro | zsh inside Ubuntu (uses dotfiles there)     | MesloLGS NF |
| Dev container          | One Dark Pro | zsh inside container (see `devcontainer/`)  | MesloLGS NF |

The font lives in your local VS Code install — containers don't need to install
it. The integrated terminal uses host fonts.
