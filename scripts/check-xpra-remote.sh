#!/usr/bin/env bash
# scripts/check-xpra-remote.sh — verify the Xpra-over-SSH server setup on this
# Linux/WSL2 host (what the ssh + xpra roles and the Windows scripts configure).
# Read-only. On WSL2 it also checks the Windows side via interop: portproxy
# target, firewall rule, and LSO/RSC on the LAN adapter.
#
# Usage: ./scripts/check-xpra-remote.sh [display] [wsl_ssh_port]
set -uo pipefail

DISPLAY_NUM="${1:-100}"
SSH_PORT="${2:-2222}"
UNIT="xpra-${DISPLAY_NUM}.service"
fails=0
warns=0

ok()   { printf '  \033[32mOK\033[0m    %s\n' "$*"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fails=$((fails + 1)); }

is_wsl=false
grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && is_wsl=true

echo "== sshd"
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
  ok "sshd is running"
else
  fail "sshd is not running"
fi
listen_ports="$(ss -Htln 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -un | tr '\n' ' ')"
if $is_wsl; then
  [[ " $listen_ports " == *" $SSH_PORT "* ]] && ok "listening on :$SSH_PORT" || fail "nothing listening on :$SSH_PORT (ssh role wsl2_ssh_enabled / setup-wsl-ssh.sh)"
else
  [[ " $listen_ports " == *" 22 "* ]] && ok "listening on :22" || warn "nothing listening on :22"
fi
if grep -rqsiE '^\s*X11Forwarding\s+yes' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/; then
  ok "X11Forwarding yes"
else
  warn "X11Forwarding not enabled (only needed for ssh -X, not for Xpra)"
fi

echo "== xpra server"
if command -v xpra >/dev/null 2>&1; then
  ver="$(xpra --version 2>/dev/null | awk '{print $2}')"
  case "$ver" in
    v[0-5].*|[0-5].*) fail "xpra $ver is too old (need 6.x from xpra.org; features.xpra installs it)" ;;
    *) ok "xpra $ver" ;;
  esac
else
  fail "xpra not installed (enable features.xpra)"
fi
if [ -e "/var/lib/systemd/linger/$USER" ]; then
  ok "linger enabled for $USER"
else
  warn "linger disabled — session will not start at boot (loginctl enable-linger $USER)"
fi
if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
  ok "$UNIT active"
else
  fail "$UNIT not active (systemctl --user status $UNIT)"
fi
if systemctl --user is-enabled --quiet "$UNIT" 2>/dev/null; then
  ok "$UNIT enabled"
else
  warn "$UNIT not enabled at login"
fi
if xpra list 2>/dev/null | grep -q "LIVE session at :${DISPLAY_NUM}"; then
  ok "LIVE session on :$DISPLAY_NUM"
else
  fail "no LIVE xpra session on :$DISPLAY_NUM"
fi
if [ -f "$HOME/.config/shell/xpra.sh" ]; then
  ok "SSH sessions export DISPLAY=:$DISPLAY_NUM (~/.config/shell/xpra.sh)"
else
  warn "~/.config/shell/xpra.sh missing — GUI apps started over SSH will not use the Xpra display"
fi

if $is_wsl; then
  echo "== Windows host (via WSL interop)"
  PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
  NETSH=/mnt/c/Windows/System32/netsh.exe
  if [ ! -x "$PS" ]; then
    warn "Windows interop unavailable; skipping host checks"
  else
    wsl_ip="$(ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
    host_ips="$("$PS" -NoProfile -Command '(Get-NetIPAddress -AddressFamily IPv4).IPAddress' 2>/dev/null | tr -d '\r')"
    if grep -qx "$wsl_ip" <<<"$host_ips"; then
      ok "mirrored networking — no portproxy needed"
    else
      target="$("$NETSH" interface portproxy show v4tov4 2>/dev/null | tr -d '\r' | awk -v p="$SSH_PORT" '$2==p {print $3}' | head -1)"
      if [ -z "$target" ]; then
        fail "no portproxy for :$SSH_PORT (run scripts/setup-windows-ssh.ps1 as admin)"
      elif [ "$target" = "$wsl_ip" ]; then
        ok "portproxy 0.0.0.0:$SSH_PORT -> $wsl_ip:$SSH_PORT"
      else
        fail "portproxy points to $target but WSL is $wsl_ip (re-run scripts/setup-windows-ssh.ps1)"
      fi
    fi
    fw="$("$PS" -NoProfile -Command "@(Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter | ? LocalPort -eq '$SSH_PORT').Count" 2>/dev/null | tr -d '\r')"
    [ "${fw:-0}" -gt 0 ] && ok "firewall allows inbound :$SSH_PORT" || fail "no inbound firewall rule for :$SSH_PORT"
    # Same default-route adapter selection as scripts/optimize-windows-network.ps1.
    offload="$("$PS" -NoProfile -Command '
      $r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix 0.0.0.0/0 | ? InterfaceAlias -notlike "vEthernet*" | Sort-Object RouteMetric | Select -First 1
      $n = $r.InterfaceAlias
      $l = Get-NetAdapterLso -Name $n -ErrorAction SilentlyContinue
      $c = Get-NetAdapterRsc -Name $n -ErrorAction SilentlyContinue
      "{0}|{1}|{2}" -f $n, [bool]($l.IPv4Enabled -or $l.IPv6Enabled), [bool]($c.IPv4Enabled -or $c.IPv6Enabled)' 2>/dev/null | tr -d '\r')"
    IFS='|' read -r adapter lso rsc <<<"$offload"
    if [ "$lso" = "False" ] && [ "$rsc" = "False" ]; then
      ok "LSOv2/RSC disabled on LAN adapter '$adapter'"
    else
      warn "LSOv2=$lso RSC=$rsc on '$adapter' — run scripts/optimize-windows-network.ps1 if Xpra stalls"
    fi
  fi
fi

echo
echo "Result: $fails failure(s), $warns warning(s)"
echo "Client: xpra attach ssh://<user>@<host>$($is_wsl && echo ":$SSH_PORT")/$DISPLAY_NUM"
[ "$fails" -eq 0 ]
