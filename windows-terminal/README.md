# Windows Terminal — One Dark Pro + MesloLGS NF

The bootstrap drops `fragment.json` into:

    %LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\dotfiles-onedarkpro\onedarkpro.json

This adds the **One Dark Pro** color scheme without touching `settings.json`.
Reference: https://learn.microsoft.com/windows/terminal/json-fragment-extensions

## Apply it (two clicks)

1. `Ctrl+,` to open Settings.
2. **Profiles → Defaults → Appearance**:
   - **Color scheme**: `One Dark Pro`
   - **Font face**: `MesloLGS NF`
   - **Font size**: 11–13pt
3. Save.

Applies to every profile (Ubuntu/WSL2, PowerShell, pwsh) unless that profile
overrides it.
