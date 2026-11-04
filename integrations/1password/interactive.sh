# shellcheck shell=bash disable=SC1090,SC1091,SC2154
if [[ -f "${XDG_CONFIG_HOME:-${HOME}/.config}/op/plugins.sh" ]]; then
  source -- "${XDG_CONFIG_HOME:-${HOME}/.config}/op/plugins.sh"
fi
