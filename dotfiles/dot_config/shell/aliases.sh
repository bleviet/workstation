###############################################################################
# aliases.sh
# Purpose: simple, discoverable aliases grouped by topic
###############################################################################

###############################################################################
## LS — use eza when available, fall back to system ls
###############################################################################
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --color=auto --group-directories-first'
  alias l='ls -lh'
  alias ll='ls -laF'
else
  alias l='ls -lh'
  alias ll='ls -laF'
fi

###############################################################################
## Navigation
###############################################################################
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

###############################################################################
## GIT
###############################################################################
alias gs='git status'
alias gso='git status -uno'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gf='git fetch'
alias gfa='git fetch --all --prune'

# gitk is a GUI tool — only define if available
if command -v gitk >/dev/null 2>&1; then
  alias gk='gitk'
  alias gka='gitk --all'
fi

# lazygit TUI — only define if available
command -v lazygit >/dev/null 2>&1 && {
  alias gg='lazygit'
  alias lg='lazygit'
}

###############################################################################
## Misc
###############################################################################
alias c='clear'
alias src='source ~/.bashrc'

# Replace cat with bat
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --style=plain'
fi

# Replace grep with ripgrep
if command -v rg >/dev/null 2>&1; then
  alias grep='rg'
fi

###############################################################################
## FZF helpers — require fzf; clipboard helpers additionally require xclip
###############################################################################
if command -v fzf >/dev/null 2>&1; then
  alias fe='$EDITOR $(fzf)'

  if command -v xclip >/dev/null 2>&1; then
    alias f='fzf | tee >(xclip -sel clip)'

    # bat is installed by dev-tools to ~/.local/bin/bat
    if command -v bat >/dev/null 2>&1; then
      alias fp="fzf --preview 'bat --style=numbers --color=always {}' | tee >(xclip -sel clip)"
    fi
  fi
fi
