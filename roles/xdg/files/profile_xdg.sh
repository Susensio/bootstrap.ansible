# Make .profile follow the XDG_CONFIG_HOME specification
_confdir=${XDG_CONFIG_HOME:-$HOME/.config}
_profile=${_confdir}/profile

# Source settings file
[ -f "${_profile}" ] && . "$_profile"

unset _confdir
unset _profile
