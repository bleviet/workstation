# AGENTS.md

Ansible + Vagrant workstation provisioning engine. **`ansible/`** is the
software-configuration engine (playbook, roles, inventory); **`local-vms/`**
holds declarative VM hardware specs. **chezmoi** owns common dotfiles (plain
`apply`, no templates, no conditionals) — don't add logic to `dotfiles/`.

## Commands

Run from repo root (required — `ansible.cfg` sets `inventory = ansible/inventory/hosts.yml`
and `roles_path = ansible/roles`).

```bash
./bootstrap.sh                                  # local bare-metal install: pip installs ansible-core,
                                                #   pulls collections, runs ansible/site.yml --limit localhost
ansible-playbook ansible/site.yml -K            # re-provision current host (prompts for sudo)
ansible-playbook ansible/site.yml -l <host>     # a host from ansible/inventory/hosts.yml
ansible-playbook ansible/site.yml --syntax-check   # fast first check; run before any role change

# Tests
./tests/run_container_tests.sh                 # Podman, parallel: debian+ubuntu+almalinux. Logs: /tmp/workstation-test-<os>.log
./tests/run_vm_tests.sh                         # Vagrant, headless test VMs.  Logs: /tmp/workstation-vm-<machine>.log
./tests/run_vm_tests.sh --desktop | --all | <name> ...
vagrant up <machine> && vagrant destroy -f <machine>     # single test/local VM lifecycle

# Remote deployment without installing Ansible locally (Podman/Docker, mounts ~/.ssh RO)
./controller/run.sh [-l <host>] [-K]            # uses ansible/site.yml + ansible/inventory/hosts.yml

# Local Jenkins GUI VM builder (cross-platform)
./scripts/setup_local_jenkins.sh                # Linux/macOS; .\scripts\setup_local_jenkins.ps1 on Windows
# → http://localhost:8080/job/workstation-vm-builder/  (admin/admin), Build with Parameters
```

## Ansible constraints

- **ansible-core >= 2.15 is asserted** by a pre_task in `ansible/site.yml`.
  System apt/dnf packages are too old — `bootstrap.sh` installs `>=2.17` via
  pip, with a `--break-system-packages` fallback for PEP 668 hosts, and patches
  `~/.bashrc` PATH. If `ansible` is not found, that PATH is the usual cause.
- **Role order in `site.yml` is load-bearing** (`user → packages → dev-tools →
  shell → chezmoi → fonts → ssh → optional fpga → desktop roles`). Respect it
  when reordering or adding roles.
- **Idempotency is enforced by the container tests**: `tests/container/Dockerfile.*`
  run the playbook twice and assert `changed=0.*failed=0`. Any role change must
  be idempotent or container tests fail. The `Pre-install Tmux plugins` post_task
  reports `changed` only when tpm prints `Installing "..."` (clone), not
  `Already installed` — keep this pattern for any plugin-preinstall task.
- `bootstrap.sh` does **not** use `--ask-become-pass` (breaks under WSL). It
  reads the sudo password into `ANSIBLE_BECOME_PASS`, then temporarily writes
  `/etc/sudoers.d/99-ansible-nopasswd` (removed via a `trap … EXIT`) as a
  workaround for an Ubuntu 26.04 sudo-prompt-matching bug. For manual runs use `-K`.
- Collections install to `~/.ansible/collections` (see `ansible.cfg`).
  `requirements.yml` pins `community.general>=8.0.0`, `ansible.posix>=1.5.0`.

## Profiles, feature flags, dev_user

- `profile` ∈ `headless | desktop-gnome | desktop-xfce | desktop-i3wm` — set per
  host in `ansible/inventory/host_vars/<hostname>.yml`. `desktop*` profiles gate
  the `desktop`/`gnome`/`xfce`/`i3wm` roles in `site.yml`.
- `features.{editor,fpga,xrdp}` are conservative-by-default; enable per host.
  Any `features.fpga.*` sub-flag pulls shared USB/JTAG libs + groups. `features.fpga`
  must be a dict (`vivado`/`quartus`/`oss`), not a scalar — the `when` in `site.yml`
  relies on attribute access.
- **`ansible_user` ≠ `dev_user`**: `ansible_user` is the SSH login (e.g.
  `vagrant` on VMs); `dev_user` is the account that receives dotfiles/dev tools
  (defaults to the SSH user; override per host). The LazyVim/tmux `post_tasks`
  become to `dev_user`.
- `scripts/add_dev_host.py` scaffolds a new host_var + inventory entry (and can
  run the playbook with `--run`).

## VM / environment gotchas

- **The `Vagrantfile` is the source of truth for VMs.** It loads
  `local-vms/vm-fpga-dev-*/vm.yml` and `tests/vm/machines.yml`. Default provider
  is `vmware_desktop` (`ENV['VAGRANT_DEFAULT_PROVIDER']`, overridable); VirtualBox
  and libvirt are also supported (libvirt overrides debian13 → `debian/trixie64`).
  Provisioning uses the `ansible_local` provisioner, so Ansible runs **inside the
  guest** — no host Ansible/WSL needed.
- The `fpga_vms` group in `ansible/inventory/hosts.yml` uses
  `ansible_connection: local` (provisioned in-guest); per-VM settings live in
  `ansible/inventory/host_vars/vm-fpga-dev-*.yml` (Vagrant aligns the guest name
  with these files).
- `local-vms/settings.yml` (tracked) can redirect VM storage via
  `vbox_base_folder` / `vmware_base_folder`.

## Style

- `.editorconfig`: 2-space indent for `yml/yaml/toml/json/sh`; LF everywhere
  (enforced via `.gitattributes`); trim trailing whitespace. YAML roles follow
  this — don't introduce tabs or CRLF.
- **Conventional commits** with scopes are the current style, e.g.
  `fix(bootstrap): …`, `fix(vagrant): …`, `docs: …`, `refactor: …`, `feat(dev-tools): …`.
- BATS tests (`tests/bats/`) source `dotfiles/dot_config/shell/functions.sh`,
  mock `docker`, and need `fzf` on PATH (`~/.local/bin`) for the `cdf` test.
- Interactive guide is `docs/index.html` (open in a browser; `docs/serve.js` is a
  zero-dep static server for the docs). Prose docs live in `docs/provisioning/`
  and `docs/dotfiles/`; `docs/wiki/` holds `vagrant-provisioning-ssh.md` and
  `network-architecture.md`. CI is defined in `Jenkinsfile` (syntax → container
  tests → VM tests on `linux-vm`/`windows-vm` agents).
