###############################################################################
# keepassxc.sh
# Purpose: unlock / lock KeePassXC from the terminal (keys reach the SSH agent)
###############################################################################
#
#   kp-unlock   ask for the master password, start KeePassXC minimized with the
#               database open; its SSH agent integration loads the keys; then
#               kp-sync (pull newer saves, push local ones)
#   kp-lock     kp-sync first (push needs the key), then lock all databases
#               (the keys leave the agent)
#   kp-status   sync state of the database (also shown in the prompt as kp:...)
#
# macOS / Linux / WSL: the local KeePassXC and agent. WSL counts as its own
# Linux machine (KeePassXC through WSLg, agent at ~/.ssh/agent.sock, its own
# clone of the database repo). KP_WSL_USE_WINDOWS=1 switches WSL back to
# driving the Windows KeePassXC and the Windows OpenSSH agent.
# The password goes to KeePassXC through a pipe (--pw-stdin): never in argv,
# the environment or the shell history.
#   KEEPASS_DB  default ~/workspace/nas/keepass/mp.kdbx, a git repo synced by
#               kp-sync (with KP_WSL_USE_WINDOWS=1: C:\Users\<you>\workspace\nas\
#               keepass\mp.kdbx, so the Windows KeePassXC saves to a local disk)

_kpxc_default_db() {
  if _kpxc_win; then
    local d
    for d in /mnt/c/Users/*/workspace/nas/keepass/mp.kdbx; do
      [ -f "$d" ] && { echo "$d"; return; }
    done
  fi
  echo "$HOME/workspace/nas/keepass/mp.kdbx"
}

_kpxc_is_wsl() { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; }
# WSL driving the Windows KeePassXC (opt-in); otherwise WSL is plain Linux.
_kpxc_win() { [ "${KP_WSL_USE_WINDOWS:-0}" = 1 ] && _kpxc_is_wsl; }

_kpxc_bin() {
  if _kpxc_win; then
    [ -x "/mnt/c/Program Files/KeePassXC/KeePassXC.exe" ] && echo "/mnt/c/Program Files/KeePassXC/KeePassXC.exe"
  elif [ -x /Applications/KeePassXC.app/Contents/MacOS/KeePassXC ]; then
    echo /Applications/KeePassXC.app/Contents/MacOS/KeePassXC
  else
    command -v keepassxc
  fi
}

_kpxc_running() {
  if _kpxc_win; then
    tasklist.exe /FI "IMAGENAME eq KeePassXC.exe" /NH 2>/dev/null | grep -qi keepassxc.exe
  elif [ "$(uname -s)" = Darwin ]; then
    pgrep -xq KeePassXC
  else
    pgrep -xu "$USER" keepassxc >/dev/null
  fi
}

# SIGTERM / WM_CLOSE = normal quit.
_kpxc_quit() {
  if _kpxc_win; then
    taskkill.exe /IM KeePassXC.exe >/dev/null 2>&1
  elif [ "$(uname -s)" = Darwin ]; then
    pkill -x KeePassXC
  else
    pkill -xu "$USER" keepassxc
  fi
}

_kpxc_keys() {
  if _kpxc_win; then
    /mnt/c/Windows/System32/OpenSSH/ssh-add.exe -l >/dev/null 2>&1
  else
    ssh-add -l >/dev/null 2>&1
  fi
}

_kpxc_list_keys() {
  if _kpxc_win; then /mnt/c/Windows/System32/OpenSSH/ssh-add.exe -l | tr -d '\r'; else ssh-add -l; fi
}

# KeePassXC adds the keys one at a time after unlocking: wait until the number
# of keys in the agent has not changed for 1 s (at most 5 s), so the list
# shows all of them, not just the first.
_kpxc_wait_keys() {
  local n last=-1 same=0
  for _ in $(seq 1 20); do
    n=$(_kpxc_list_keys 2>/dev/null | grep -c 'SHA256:')
    if [ "$n" = "$last" ]; then
      same=$((same + 1))
      [ "$same" -ge 4 ] && return 0
    else
      same=0; last=$n
    fi
    sleep 0.25
  done
}

# The database path as KeePassXC sees it. On WSL a file below a drvfs mount of
# a Windows network share (e.g. ~/synology -> \\nas\home) becomes \\nas\home\...
_kpxc_db_arg() {
  local db=$1 mnt src rel
  if ! _kpxc_win; then echo "$db"; return; fi
  mnt=$(findmnt -n -o TARGET -T "$db" 2>/dev/null)
  src=$(findmnt -n -o SOURCE -T "$db" 2>/dev/null)
  case "$src" in
    '\\'*) rel=${db#"$mnt"/}; printf '%s\\%s\n' "$src" "$(printf '%s' "$rel" | tr '/' '\\')" ;;
    *) wslpath -w "$db" ;;
  esac
}

# Pull/push the database repo (kp-sync is silent when the file is not in git).
_kpxc_sync() {
  command -v kp-sync >/dev/null 2>&1 || return 0
  KEEPASS_DB="$1" kp-sync --auto
  return 0
}

# WSLg's Wayland compositor crashes on KeePassXC ("The Wayland connection
# broke"); X11 through XWayland works. Prints the env assignment for env(1).
_kpxc_qpa() {
  if _kpxc_is_wsl && ! _kpxc_win; then echo "QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-xcb}"; else echo "KPXC_NOOP=1"; fi
}

kp-unlock() {
  local bin db pw log
  bin=$(_kpxc_bin)
  [ -n "$bin" ] || { echo "kp-unlock: KeePassXC not installed" >&2; return 1; }
  # Linux (not WSL): KeePassXC is a GUI app and needs a desktop session.
  if [ "$(uname -s)" = Linux ] && ! _kpxc_win && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    echo "kp-unlock: no desktop session here (DISPLAY not set); run it in a terminal on the desktop" >&2
    return 1
  fi
  db="${KEEPASS_DB:-$(_kpxc_default_db)}"
  [ -f "$db" ] || { echo "kp-unlock: database not found: $db (clone your KeePass git repo to ~/workspace/nas/keepass, or set KEEPASS_DB)" >&2; return 1; }

  # Keys in the agent = unlocked, wherever KeePassXC runs. Checked first: the
  # process check cannot see other login sessions (e.g. over SSH on Windows).
  if _kpxc_keys; then echo "kp-unlock: already unlocked"; _kpxc_list_keys; _kpxc_sync "$db"; return 0; fi

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
  # --minimized exists only in newer KeePassXC (not in Ubuntu 24.04's 2.7.6).
  # On WSL the Windows build would show --help as a dialog: assume a current
  # Windows install there.
  local opt=--minimized
  if ! _kpxc_win && ! env "$(_kpxc_qpa)" "$bin" --help 2>/dev/null | grep -q -- '--minimized'; then opt=""; fi
  # Subshell: no "[1] <pid>" job message, and the app outlives this shell.
  ( printf '%s\n' "$pw" | nohup env "$(_kpxc_qpa)" "$bin" --pw-stdin $opt "$(_kpxc_db_arg "$db")" >"$log" 2>&1 & )
  pw=; unset pw

  local i
  for i in $(seq 1 120); do
    if _kpxc_keys; then _kpxc_wait_keys; _kpxc_list_keys; _kpxc_sync "$db"; return 0; fi
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
  # Push before locking: the SSH key for git leaves the agent with the lock.
  _kpxc_sync "${KEEPASS_DB:-$(_kpxc_default_db)}"
  "$bin" --lock >/dev/null 2>&1
  echo "KeePassXC locked"
}
