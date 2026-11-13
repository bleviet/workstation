###############################################################################
# exports.sh
# Purpose: environment variables and exports used by shell configs
###############################################################################

###############################################################################
## Git prompt settings
###############################################################################
export GIT_PS1_SHOWDIRTYSTATE=1
export GIT_PS1_SHOWUNTRACKEDFILES=1

###############################################################################
## Colors + Editor
###############################################################################
# Set LS_COLORS based on the Dracula theme
export LS_COLORS='di=35:ln=36:ex=32:bd=33;44:cd=33;41:pi=35:so=33:*.tar=31:*.gz=31:*.zip=31:*.jpg=35:*.jpeg=35:*.png=35:*.gif=35:*.bmp=35:*.txt=37'

# Dracula theme for Bat (modern cat)
export BAT_THEME="Dracula"

# Dracula theme for fzf
export FZF_DEFAULT_OPTS="--color=fg:#f8f8f2,bg:#282a36,hl:#bd93f9 --color=fg+:#f8f8f2,bg+:#44475a,hl+:#bd93f9 --color=info:#ffb86c,prompt:#50fa7b,pointer:#ff79c6 --color=marker:#ff79c6,spinner:#ffb86c,header:#6272a4"

export EDITOR=nvim

###############################################################################
## PATH
###############################################################################
export PATH="$HOME/.local/bin:$PATH"

if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

###############################################################################
## Quartus Lite (Intel/Altera) — $HOME/tools/altera_lite
###############################################################################
_ALTERA_ROOT="$HOME/tools/altera_lite/25.1std"
if [ -d "$_ALTERA_ROOT" ]; then
  export QUARTUS_ROOTDIR="$_ALTERA_ROOT/quartus"
  export PATH="$_ALTERA_ROOT/quartus/bin:$PATH"
  export PATH="$_ALTERA_ROOT/questa_fse/bin:$PATH"
  export PATH="$_ALTERA_ROOT/nios2eds/bin:$PATH"
fi
unset _ALTERA_ROOT

###############################################################################
## Vivado (AMD/Xilinx) — $HOME/tools/Xilinx/Vivado
###############################################################################
if [ -f "$HOME/tools/Xilinx/Vivado/2024.2/settings64.sh" ]; then
  . "$HOME/tools/Xilinx/Vivado/2024.2/settings64.sh"
fi
