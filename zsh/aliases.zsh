# =============================================================================
# Aliases
# =============================================================================
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias grep='grep --color=auto'
alias zshconfig='${EDITOR} $DOTFILES/zsh/.zshrc'
alias starshipconfig='${EDITOR} $DOTFILES/starship/starship.toml'
alias reload='exec zsh'
alias g='git'
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate'
if [ -e /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  alias op='op.exe'
fi
