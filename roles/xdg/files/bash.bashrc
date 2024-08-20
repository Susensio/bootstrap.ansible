# Make bash follow the XDG_CONFIG_HOME specification
_confdir=${XDG_CONFIG_HOME:-$HOME/.config}/bash
_bashrc=${_confdir}/bashrc
_datadir=${XDG_DATA_HOME:-$HOME/.local/share}/bash
_history=${_datadir}/history

# Source settings file
[ -f "$_bashrc" ] && . "$_bashrc"

# Change the location of the history file by setting the environment variable
[ ! -d "$_datadir" ] && mkdir -p "$_datadir"
HISTFILE=$_datadir/history

unset _confdir
unset _bashrc
unset _datadir
unset _history
