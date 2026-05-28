###############################################################################
# functions.sh
# Purpose: small, portable shell helper functions used across configurations
###############################################################################

###############################################################################
# Git helpers
###############################################################################
parse_git_branch() {
  git branch 2>/dev/null | grep '\*' | sed 's/* //'
}

gkf() {
  local file
  file=$(fzf)
  if [[ -n "$file" ]]; then
    gitk "$file"
  fi
}

###############################################################################
# Navigation helpers
###############################################################################
cdf() {
  local file
  file=$(fzf)
  if [[ -n "$file" ]]; then
    cd "$(dirname "$file")"
  fi
}

###############################################################################
# FPGA / EDA helpers
###############################################################################

# quartus-gui: Start the Quartus Prime GUI inside the cvsoc Docker image,
#              mounting the current directory as /work inside the container.
#
# Usage: cd /path/to/your/project && quartus-gui
#
# Supports both X11 (Linux) and WSLg (Windows 11 + WSL2).
quartus-gui() {
  xhost +local:docker 2>/dev/null || true
  docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    -e DISPLAY="$DISPLAY" \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /mnt/wslg:/mnt/wslg \
    -e WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
    -e XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir \
    -v "$(pwd)":/work \
    cvsoc/quartus:23.1 \
    bash -c "cd /work && quartus 2>/dev/null || quartus"
}

###############################################################################
# Yank helper (yazi wrapper)
###############################################################################
y() {
  local tmp cwd
  tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
  rm -f -- "$tmp"
}