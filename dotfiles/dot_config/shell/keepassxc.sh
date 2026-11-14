###############################################################################
# keepassxc.sh
# Purpose: unlock / lock KeePassXC from the terminal (keys reach the SSH agent)
###############################################################################
#
#   kp-unlock   ask for the master password, start KeePassXC minimized with the
#               database open; its SSH agent integration loads the keys
#   kp-lock     lock all databases (the keys leave the agent)
#
# macOS / Linux: the local KeePassXC and agent. WSL: the Windows KeePassXC and
# the Windows OpenSSH agent (the one git in WSL uses via ssh.exe).
# The password goes to KeePassXC through a pipe (--pw-stdin): never in argv,
# the environment or the shell history.
#   KEEPASS_DB  default ~/synology/Documents/Personal/keepass/mp.kdbx

_kpxc_is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }

_kpxc_bin() {
  if _kpxc_is_wsl; then
    [ -x "/mnt/c/Program Files/KeePassXC/KeePassXC.exe" ] && echo "/mnt/c/Program Files/KeePassXC/KeePassXC.exe"
  elif [ -x /Applications/KeePassXC.app/Contents/MacOS/KeePassXC ]; then
    echo /Applications/KeePassXC.app/Contents/MacOS/KeePassXC
  else
    command -v keepassxc
  fi
}

_kpxc_running() {
  if _kpxc_is_wsl; then
    tasklist.exe /FI "IMAGENAME eq KeePassXC.exe" /NH 2>/dev/null | grep -qi keepassxc.exe
  elif [ "$(uname -s)" = Darwin ]; then
    pgrep -xq KeePassXC
  else
    pgrep -xu "$USER" keepassxc >/dev/null
  fi
}

# SIGTERM / WM_CLOSE = normal quit.
_kpxc_quit() {
  if _kpxc_is_wsl; then
    taskkill.exe /IM KeePassXC.exe >/dev/null 2>&1
  elif [ "$(uname -s)" = Darwin ]; then
    pkill -x KeePassXC
  else
    pkill -xu "$USER" keepassxc
  fi
}

_kpxc_keys() {
  if _kpxc_is_wsl; then
    /mnt/c/Windows/System32/OpenSSH/ssh-add.exe -l >/dev/null 2>&1
  else
    ssh-add -l >/dev/null 2>&1
  fi
}

_kpxc_list_keys() {
  if _kpxc_is_wsl; then /mnt/c/Windows/System32/OpenSSH/ssh-add.exe -l | tr -d '\r'; else ssh-add -l; fi
}

# The database path as KeePassXC sees it. On WSL a file below a drvfs mount of
# a Windows network share (e.g. ~/synology -> \\nas\home) becomes \\nas\home\...
_kpxc_db_arg() {
  local db=$1 mnt src rel
  if ! _kpxc_is_wsl; then echo "$db"; return; fi
  mnt=$(findmnt -n -o TARGET -T "$db" 2>/dev/null)
  src=$(findmnt -n -o SOURCE -T "$db" 2>/dev/null)
  case "$src" in
    '\\'*) rel=${db#"$mnt"/}; printf '%s\\%s\n' "$src" "$(printf '%s' "$rel" | tr '/' '\\')" ;;
    *) wslpath -w "$db" ;;
  esac
}

kp-unlock() {
  local bin db pw log
  bin=$(_kpxc_bin)
  [ -n "$bin" ] || { echo "kp-unlock: KeePassXC not installed" >&2; return 1; }
  # Linux (not WSL): KeePassXC is a GUI app and needs a desktop session.
  if [ "$(uname -s)" = Linux ] && ! _kpxc_is_wsl && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "kp-unlock: no desktop session here (DISPLAY not set); run it in a terminal on the desktop" >&2
    return 1
  fi
  db="${KEEPASS_DB:-$HOME/synology/Documents/Personal/keepass/mp.kdbx}"
  [ -f "$db" ] || { echo "kp-unlock: database not found: $db (NAS mounted?)" >&2; return 1; }

  # Keys in the agent = unlocked, wherever KeePassXC runs. Checked first: the
  # process check cannot see other login sessions (e.g. over SSH on Windows).
  if _kpxc_keys; then echo "kp-unlock: already unlocked"; _kpxc_list_keys; return 0; fi

  if _kpxc_running; then
    # A second start cannot unlock a running instance; it is locked, so
    # nothing unsaved is lost by quitting it.
    _kpxc_quit
    for _ in $(seq 1 20); do _kpxc_running || break; sleep 0.25; done
  fi

  printf 'KeePassXC master password: ' >&2
  read -rs pw; echo >&2
  log="${XDG_CACHE_HOME:-$HOME/.cache}/kp-unlock.log"
  mkdir -p "$(dirname "$log")"
  printf '%s\n' "$pw" | nohup "$bin" --pw-stdin --minimized "$(_kpxc_db_arg "$db")" >"$log" 2>&1 &
  disown 2>/dev/null
  pw=; unset pw

  local i
  for i in $(seq 1 120); do
    if _kpxc_keys; then _kpxc_list_keys; return 0; fi
    # KeePassXC quit early: wrong password, no display, ... show why. Only
    # after 2 s: right after the start it may not be listed yet.
    if [ "$i" -gt 8 ] && ! _kpxc_running; then
      echo "kp-unlock: KeePassXC exited without unlocking (wrong password?). Its last messages:" >&2
      tail -n 5 "$log" >&2
      return 1
    fi
    sleep 0.25
  done
  echo "kp-unlock: no keys in the agent after 30 s; KeePassXC log: $log" >&2
  return 1
}

kp-lock() {
  local bin
  bin=$(_kpxc_bin)
  [ -n "$bin" ] || return 1
  _kpxc_running || { echo "kp-lock: KeePassXC is not running"; return 0; }
  "$bin" --lock >/dev/null 2>&1
  echo "KeePassXC locked"
}
