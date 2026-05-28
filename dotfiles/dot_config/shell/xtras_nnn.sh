###############################################################################
# xtras_nnn.sh
# Purpose: helpers for nnn file manager (cd-on-quit behavior)
###############################################################################

export NNN_PLUG='z:autojump;f:fzcd;e:fzopen;d:diffs'

###############################################################################
# nnn launcher with cd-on-quit support
###############################################################################
function n() {
  # Block nesting of nnn in subshells
  [ "${NNNLVL:-0}" -eq 0 ] || {
    echo "nnn is already running"
    return
  }

  # The behaviour is set to cd on quit (nnn checks if NNN_TMPFILE is set)
  export NNN_TMPFILE="${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.lastd"

  # The command builtin allows one to alias nnn to n, if desired, without
  # making an infinitely recursive alias
  command nnn "$@"

  [ ! -f "$NNN_TMPFILE" ] || {
    . "$NNN_TMPFILE"
    rm -f -- "$NNN_TMPFILE" >/dev/null
  }
}
