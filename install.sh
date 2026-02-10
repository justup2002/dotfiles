#!/bin/bash
set -e

# 1. Ensure Zsh is installed
if ! command -v zsh &> /dev/null; then
  echo "Zsh not found. Installing..."
  sudo apt-get update && sudo apt-get install -y zsh
fi

# 2. Install Oh My Zsh (if not already present)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# 3. Install Powerlevel10k
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
  echo "Cloning Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
fi

# 4. Install your Plugins (Replace these URLs with the ones you use!)
# Example: zsh-autosuggestions and zsh-syntax-highlighting
PLUGIN_DIR=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins

if [ ! -d "$PLUGIN_DIR/zsh-autosuggestions" ]; then
  echo "Cloning zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

if [ ! -d "$PLUGIN_DIR/zsh-syntax-highlighting" ]; then
  echo "Cloning zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
fi

# 5. Symlink your config files
# This replaces the container's default configs with yours
ln -sf "$PWD/.zshrc" "$HOME/.zshrc"
ln -sf "$PWD/.p10k.zsh" "$HOME/.p10k.zsh"

echo "Dotfiles installation complete!"