###############################################################################
# start_ssh_agent.sh
# Purpose: start ssh-agent if necessary and add default key
###############################################################################

start_ssh_agent() {
  if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
  fi
  ssh-add -l &>/dev/null
  if [ $? -ne 0 ]; then
    ssh-add ~/.ssh/id_rsa # Adjust the path to your private key if necessary
  fi
}

# Auto-start the agent
start_ssh_agent
