###############################################################################
# keepassxc.sh
# Purpose: unlock / lock KeePassXC from the terminal (keys reach the SSH agent)
###############################################################################
#
#   kp-unlock   ask for the master password, start KeePassXC minimized with the
#               database open; its SSH agent integration loads the keys
#   kp-lock     lock all databases (the keys leave the agent)
#
# The password goes to KeePassXC through a pipe (--pw-stdin): never in argv,
# the environment or the shell history.
#   KEEPASS_DB  default ~/synology/Documents/Personal/keepass/mp.kdbx

_kpxc_bin() {
  if [ -x /Applications/KeePassXC.app/Contents/MacOS/KeePassXC ]; then
    echo /Applications/KeePassXC.app/Contents/MacOS/KeePassXC
  else
    command -v keepassxc
  fi
}

_kpxc_running() {
  if [ "$(uname -s)" = Darwin ]; then pgrep -xq KeePassXC; else pgrep -xu "$USER" keepassxc >/dev/null; fi
}

_kpxc_keys() { ssh-add -l >/dev/null 2>&1; }

kp-unlock() {
  local bin db pw
  bin=$(_kpxc_bin) || { echo "kp-unlock: KeePassXC not installed" >&2; return 1; }
  db="${KEEPASS_DB:-$HOME/synology/Documents/Personal/keepass/mp.kdbx}"
  [ -f "$db" ] || { echo "kp-unlock: database not found: $db (NAS mounted?)" >&2; return 1; }

  if _kpxc_running; then
    if _kpxc_keys; then echo "kp-unlock: already unlocked"; ssh-add -l; return 0; fi
    # A second start cannot unlock a running instance; it is locked, so
    # nothing unsaved is lost by quitting it.
    # SIGTERM = normal quit (no macOS automation prompt as with osascript).
    if [ "$(uname -s)" = Darwin ]; then pkill -x KeePassXC; else pkill -xu "$USER" keepassxc; fi
    for _ in $(seq 1 20); do _kpxc_running || break; sleep 0.25; done
  fi

  printf 'KeePassXC master password: ' >&2
  read -rs pw; echo >&2
  printf '%s\n' "$pw" | nohup "$bin" --pw-stdin --minimized "$db" >/dev/null 2>&1 &
  disown 2>/dev/null
  pw=; unset pw

  for _ in $(seq 1 40); do
    if _kpxc_keys; then ssh-add -l; return 0; fi
    sleep 0.25
  done
  echo "kp-unlock: no keys in the agent after 10 s (wrong password?)" >&2
  return 1
}

kp-lock() {
  local bin
  bin=$(_kpxc_bin) || return 1
  _kpxc_running || { echo "kp-lock: KeePassXC is not running"; return 0; }
  "$bin" --lock >/dev/null 2>&1
  echo "KeePassXC locked"
}
