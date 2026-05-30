# Remote deployment

## From an admin PC (Ansible installed)

Add target hosts to `provisioning/inventory/hosts.yml`, then run:

```bash
ansible-playbook provisioning/site.yml -K -l my_laptop
```

## From a controller container (no Ansible on admin PC)

Build and run the containerised Ansible controller — works with Podman or
Docker:

```bash
# Run site.yml against all hosts
./controller/run.sh

# Limit to a single host
./controller/run.sh -l my_laptop

# Limit to servers, prompt for become password
./controller/run.sh -l servers -K
```

The container mounts `~/.ssh` read-only so your SSH keys are available without
embedding them in the image.
