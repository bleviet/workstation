###############################################################################
# start_ssh_agent.sh
# Purpose: start ssh-agent if necessary and add default key
###############################################################################

# A dedicated agent on ~/.ssh/agent.sock (e.g. one with SSH_ASKPASS, needed
# for keys that require confirmation on each use) wins over the system agent.
[ -S "$HOME/.ssh/agent.sock" ] && export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"

# Only run in interactive shells — non-interactive shells (like those started
# by Ansible, rsync, or scp) must stay silent on stdout.
[[ $- == *i* ]] || return 0

start_ssh_agent() {
  if [ -z "$SSH_AUTH_SOCK" ]; then
    # Redirect stdout so "Agent pid XXXX" (echoed by ssh-agent -s) is silenced.
    eval "$(ssh-agent -s)" > /dev/null
  fi
  ssh-add -l &>/dev/null
  if [ $? -ne 0 ] && [ -f "$HOME/.ssh/id_rsa" ]; then
    ssh-add "$HOME/.ssh/id_rsa"
  fi
}

start_ssh_agent
