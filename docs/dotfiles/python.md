# Python workflow — uv + direnv

Python environments are managed with **uv** and activated automatically with
**direnv**. There is no conda/miniconda — `uv` handles both the Python version
and the packages.

## How it works

| Tool | Role |
|---|---|
| `uv` | Creates virtual environments, installs packages, manages Python versions |
| `direnv` | Auto-activates `.venv` when you enter a project directory; deactivates on exit |
| `mkvenv` | Shell function that wires them together for a new project |

Both are installed by Ansible at provisioning time — no manual setup needed.
Python 3.13 is pre-fetched by `uv python install 3.13` so `mkvenv` works
immediately without a network fetch.

## Quick start

```bash
cd ~/projects/my-hdl-design
mkvenv
# → creates .venv (Python 3.13)
# → writes .envrc and runs `direnv allow .`
# → installs pytest, cocotb, cocotbext-axi
# → venv is active immediately

pytest            # available right away
uv pip install <extra-package>

cd ~              # venv deactivates automatically
cd ~/projects/my-hdl-design   # reactivates
```

## mkvenv

```
mkvenv [python_version]
```

| Argument | Default | Example |
|---|---|---|
| `python_version` | `3.13` | `mkvenv 3.12` |

Steps performed:

1. `uv venv --python python<version> .venv` — creates the virtual environment
2. Writes `.envrc` containing `source .venv/bin/activate` (skipped if a
   `.envrc` already exists so existing configurations are not overwritten)
3. `direnv allow .` — approves the `.envrc` so direnv fires on every `cd`
4. Installs `~/.config/uv/requirements.txt` into the venv

```bash
mkvenv           # Python 3.13 + base packages
mkvenv 3.12      # Python 3.12 + base packages
mkvenv 3.11      # Python 3.11 + base packages
```

## Base packages

Every new venv gets the packages in `~/.config/uv/requirements.txt`
(a dotfile managed by chezmoi):

```
pytest
cocotb
cocotbext-axi
```

Edit this file to change the global baseline — add `ruff`, `mypy`, `black`, or
anything else you want in every project. Per-project additions go in the
project's own `requirements.txt` or `pyproject.toml`.

## Adding packages to a project

```bash
# Add a single package
uv pip install numpy

# Install from a project requirements file
uv pip install -r requirements.txt

# Install from pyproject.toml
uv pip install -e .
```

## direnv integration

direnv watches each directory for an `.envrc` file and evaluates it whenever
you `cd` into the directory. The `.envrc` written by `mkvenv` contains:

```bash
source .venv/bin/activate
```

The direnv shell hook is installed via `~/.config/shell/direnv.sh`, which is
sourced by both `.bashrc` and `.zshrc` through the `~/.config/shell/*.sh` glob.

> **Approving an existing `.envrc`:** if a `.envrc` was created manually or
> by another tool, run `direnv allow .` once to let direnv evaluate it.

## UV_PYTHON default

`~/.config/shell/uv.sh` exports `UV_PYTHON=3.13`, so plain `uv venv` and
`uv run` also default to Python 3.13 without specifying a version explicitly.
Override per-project by setting `UV_PYTHON` in the project's `.envrc`:

```bash
# .envrc
export UV_PYTHON=3.12
source .venv/bin/activate
```

## Python version management

uv manages its own Python installations independently of the system Python:

```bash
uv python list              # show available / installed versions
uv python install 3.12      # download and cache Python 3.12
uv python install 3.11      # download and cache Python 3.11
```

Installed versions are cached in `~/.local/share/uv/python/` and reused across
all projects.
