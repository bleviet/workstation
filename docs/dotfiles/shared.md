# Dotfiles — multiple users

Use this flow when **several people** share this repo. Each person keeps their
dotfiles in their own repository. Set `chezmoi_init_repo` per host so the
chezmoi role clones the right dotfiles for each user.

## Configure per host

```yaml
# ansible/inventory/host_vars/alice_laptop.yml
chezmoi_init_repo: "https://github.com/alice/dotfiles"
```

On the first provisioning run chezmoi clones the repo to
`~/.local/share/chezmoi` and applies it. On subsequent runs it re-applies from
the existing clone without re-cloning.

## Edit and commit dotfiles

```bash
chezmoi edit ~/.bashrc            # edit via chezmoi
chezmoi cd                        # cd into ~/.local/share/chezmoi
git add -A && git commit && git push
```

---

## SSH authentication

### Interactive (passphrase-protected personal key)

The role forwards your SSH agent socket into the chezmoi process so the agent
handles the passphrase transparently. Load your key once before provisioning:

```bash
ssh-add ~/.ssh/id_ed25519
ansible-playbook ansible/site.yml
```

For remote hosts, enable agent forwarding in `~/.ssh/config`:

```
Host my-server
    ForwardAgent yes
```

If no agent socket is found for an SSH URL, the playbook fails immediately with
a clear message instead of hanging on a passphrase prompt.

### Unattended / CI (passphrase-less deployment key)

For runs where no interactive SSH agent is available, use a dedicated
passphrase-less deployment key and set `chezmoi_ssh_key_file`. The key is
injected via `GIT_SSH_COMMAND` — no agent required.

**1. Generate a deployment key (no passphrase)**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_deploy -N ""
```

**2. Add the public key to your dotfiles repo**

```bash
cat ~/.ssh/id_ed25519_deploy.pub
# → paste into GitHub: Settings → Deploy keys → Add deploy key (read-only)
```

**3. Configure the host**

```yaml
# ansible/inventory/host_vars/ci_runner.yml
chezmoi_init_repo: "git@github.com:alice/dotfiles"
chezmoi_ssh_key_file: "~/.ssh/id_ed25519_deploy"
```

The deployment key must have **read-only** access to the dotfiles repo.

---

## Auth method summary

| `chezmoi_ssh_key_file` | URL type | Auth method |
|---|---|---|
| unset | HTTPS | No auth needed |
| unset | SSH (`git@…`) | SSH agent (`SSH_AUTH_SOCK`) — run `ssh-add` first |
| set | SSH (`git@…`) | Deployment key (`GIT_SSH_COMMAND`) — unattended |
