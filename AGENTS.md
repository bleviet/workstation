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
./tests/run_container_tests.sh                 # Podman, parallel: debian+ubuntu. Logs: /tmp/workstation-test-<os>.log
./tests/run_vm_tests.sh                         # Vagrant, headless test VMs.  Logs: /tmp/workstation-vm-<machine>.log
./tests/run_vm_tests.sh --desktop | --all | <name> ...
./tests/run_proxmox_tests.py [--desktop|--all|<name>] [--keep]   # throwaway linked-clone VMs on Proxmox (needs PROXMOX_TOKEN_ID/SECRET); --templates once, --destroy, --list
vagrant up <machine> && vagrant destroy -f <machine>     # single test/local VM lifecycle

# Remote deployment without installing Ansible locally (Podman/Docker, mounts ~/.ssh RO)
./controller/run.sh [-l <host>] [-K]            # uses ansible/site.yml + ansible/inventory/hosts.yml

# Local Jenkins GUI VM builder (cross-platform)
./scripts/setup_local_jenkins.sh                # Linux/macOS; .\scripts\setup_local_jenkins.ps1 on Windows
# → http://localhost:8080/job/workstation-vm-builder/  (admin/admin), Build with Parameters

# WSL2 named instances (Windows only — run from elevated PowerShell)
.\scripts\new_wsl_instance.ps1 -SpecFile local-vms\wsl-fpga-dev\wsl.yml   # create instance from spec
.\scripts\new_wsl_instance.ps1 -SpecFile local-vms\wsl-dev-ubuntu26\wsl.yml -Provision  # create + provision
ansible-playbook ansible/site.yml -l wsl-fpga-dev   # re-provision a single WSL instance
ansible-playbook ansible/site.yml -l wsl_instances  # provision all WSL instances at once
.\scripts\attach-jtag-usb.ps1                        # attach JTAG boards (USB-Blaster, Digilent) to wsl-fpga-dev
.\scripts\attach-jtag-usb.ps1 -Distro wsl-fpga-dev -List  # list all USB devices
.\scripts\setup-windows-ssh.ps1                      # expose Windows (:22) + WSL2 (:2222) SSH on LAN
.\scripts\setup-windows-ssh.ps1 -WslDistro wsl-fpga-dev   # target a specific WSL2 instance
.\scripts\optimize-windows-network.ps1 [-FixBridge]   # report / remove a Wi-Fi-only network bridge (stalled downloads, SMB, Xpra)
./scripts/setup-wsl-ssh.sh                           # standalone WSL2 sshd setup on port 2222 (automated for wsl_instances)
./scripts/check-xpra-remote.sh                       # verify sshd/xpra session/portproxy/no Wi-Fi bridge from inside WSL2
```

## Ansible constraints

- **ansible-core >= 2.15 is asserted** by a pre_task in `ansible/site.yml`.
  System apt packages are too old — `bootstrap.sh` installs `>=2.17` via
  pip, with a `--break-system-packages` fallback for PEP 668 hosts, and patches
  `~/.bashrc` PATH. If `ansible` is not found, that PATH is the usual cause.
- **Role order in `site.yml` is load-bearing** (`user → packages → dev-tools →
  shell → chezmoi → fonts → ssh → workspace → optional fpga → desktop roles → xrdp → xpra`). Respect it
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
- `features.{editor,fpga,xrdp,xpra}` are conservative-by-default; enable per host
  (`localhost` auto-enables `xpra` on WSL2 + macOS). `xpra` is server-side on
  Debian/Ubuntu only, client-side on macOS; it never restarts a running session (that kills
  GUI apps). See `docs/provisioning/xpra-remote-gui.md`.
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

- **No emojis** in commit messages, code, comments, docs or generated files
  (plain text, e.g. `Done`, not `Done` plus a check-mark emoji). Tk/libXft < 2.3.5 crashes gitk on
  color emoji glyphs, and the repo style is plain text. Enforced by
  `.githooks/` (commit-msg + pre-commit; `bootstrap.sh` sets
  `git config core.hooksPath .githooks`, or run it manually after cloning).
  Box drawing (`──`), arrows (`→`) and the starship chevrons are fine.
- **No secrets in commits**: `.githooks/pre-commit` runs `gitleaks` on staged
  changes and blocks the commit on a finding (gitleaks is installed by the
  `dev-tools` role). Never bypass it with `--no-verify`; for a false positive
  add a `gitleaks:allow` comment on that line.
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
