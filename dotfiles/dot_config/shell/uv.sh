###############################################################################
# uv.sh
# Purpose: uv Python package manager configuration and project venv helpers.
###############################################################################

# Default Python version used by `uv venv`, `uv run`, and `mkvenv`.
export UV_PYTHON="3.13"

# mkvenv [python_version]
#
# Create a project-local .venv for the current directory:
#   1. Creates .venv using uv with the requested Python version (default 3.13).
#   2. Writes a .envrc that activates the venv; direnv picks it up automatically.
#   3. Runs `direnv allow .` so no manual approval step is needed.
#   4. Installs the global base requirements from ~/.config/uv/requirements.txt
#      so every new project starts with pytest, cocotb, etc. already available.
#
# Examples:
#   mkvenv          # Python 3.13
#   mkvenv 3.12     # Python 3.12
mkvenv() {
  local py="${1:-3.13}"

  uv venv --python "python${py}" .venv || return 1

  if [ ! -f .envrc ]; then
    printf 'source .venv/bin/activate\n' > .envrc
  fi

  direnv allow .

  local req="$HOME/.config/uv/requirements.txt"
  if [ -f "$req" ]; then
    uv pip install -r "$req"
  fi

  echo "Created .venv (python${py})"
  [ -f "$req" ] && echo "Installed base packages from ~/.config/uv/requirements.txt"
}
