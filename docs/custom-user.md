# Custom developer user

By default the playbook provisions the account it connects as (`vagrant` on a
Vagrant VM, your own user on `localhost`). Set `dev_user` in
`inventory/host_vars/<hostname>.yml` to create and provision a separate named
account instead.

## What happens when dev_user is set

The `user` role runs first and:

1. Creates the account (shell: `/bin/zsh`, home directory auto-created).
2. Adds it to `sudo` (Debian/Ubuntu) or `wheel` (AlmaLinux/RHEL).
3. Drops a `NOPASSWD` entry in `/etc/sudoers.d/<dev_user>` so the account can
   install packages without a password prompt.

All subsequent roles (dev-tools, shell, chezmoi, fonts) then install into
`/home/<dev_user>/` rather than the SSH user's home.

## Example — shared team machine

```yaml
# inventory/host_vars/devbox.yml
profile: desktop-xfce

dev_user: bach

features:
  fpga: false
  xrdp: true      # RDP access from Windows
```

Provision with:

```bash
ansible-playbook playbooks/site.yml -l devbox
```

Ansible connects as its normal SSH user (which must have sudo), the `user`
role creates `bach`, and the rest of the playbook configures `bach`'s
environment.

## Example — Vagrant VM with a custom user

Pass `dev_user` via `--extra-vars` when bringing up a Vagrant machine:

```bash
vagrant up ubuntu --provider=libvirt
vagrant provision ubuntu -- --extra-vars '{"dev_user": "bach"}'
```

Or set it permanently in the `MACHINES` table in `tests/vagrant/Vagrantfile`:

```ruby
"ubuntu" => { box: "bento/ubuntu-24.04", profile: "headless",
               memory: 2048, cpus: 2, gui: false, dev_user: "bach" },
```

and pass it through `extra_vars` alongside the existing keys:

```ruby
extra_vars = {
  "profile"   => cfg[:profile],
  "dev_user"  => cfg.fetch(:dev_user, "vagrant"),
  "features"  => { ... },
}
```

## Default behaviour (no change required)

When `dev_user` is not set it resolves to `ansible_user_id` — the SSH user
Ansible connects as. No account is created, no sudo entry is written, and all
paths resolve to that user's existing home directory.

## Connecting as the new user after provisioning

Once provisioned you can SSH directly as the developer account:

```bash
ssh bach@devbox
```

The account has passwordless sudo, `zsh` as the default shell, and all the
dev tools, dotfiles, and shell config installed in `/home/bach/`.
