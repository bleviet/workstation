###############################################################################
# start_ssh_agent.sh
# Purpose: use the one SSH agent at ~/.ssh/agent.sock
###############################################################################

# The agent runs outside the shell: a launchd job on macOS, the systemd user
# unit ssh-agent-sock.service on Linux (Ansible shell role). KeePassXC loads
# the keys into it (Settings -> SSH Agent -> SSH_AUTH_SOCK override =
# ~/.ssh/agent.sock). Shells only connect, so they never pile up agents.

_agent_sock="$HOME/.ssh/agent.sock"

# A socket left over from a dead agent (exit code 2 = cannot connect).
if [ -S "$_agent_sock" ]; then
  SSH_AUTH_SOCK="$_agent_sock" ssh-add -l >/dev/null 2>&1
  [ $? -eq 2 ] && rm -f "$_agent_sock"
fi

if [ -S "$_agent_sock" ]; then
  export SSH_AUTH_SOCK="$_agent_sock"
elif [ -z "${SSH_AUTH_SOCK:-}" ] && [[ $- == *i* ]] && command -v ssh-agent >/dev/null 2>&1; then
  # No managed agent (e.g. no systemd): start one at the fixed socket, once;
  # later shells find the socket and reuse it.
  mkdir -p -m 700 "$HOME/.ssh"
  ssh-agent -a "$_agent_sock" >/dev/null 2>&1 && export SSH_AUTH_SOCK="$_agent_sock"
fi

unset _agent_sock
