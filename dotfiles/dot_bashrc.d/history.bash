# History options (better experience)
HISTCONTROL=ignoredups:erasedups # Avoid duplicate entries in history
shopt -s histappend              # Append to history, don't overwrite it

# History is shared across multiple terminal sessions in real-time, so commands entered in one terminal will appear in the history of others.
if [ -z "$PROMPT_COMMAND" ]; then
	PROMPT_COMMAND="history -a; history -c; history -r"
else
	PROMPT_COMMAND="history -a; history -c; history -r; $PROMPT_COMMAND"
fi
