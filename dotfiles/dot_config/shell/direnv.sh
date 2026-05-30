###############################################################################
# direnv.sh
# Purpose: hook direnv into the current shell so .envrc files are evaluated
#          automatically on directory change.
###############################################################################
if command -v direnv >/dev/null 2>&1; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(direnv hook zsh)"
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(direnv hook bash)"
  fi
fi
