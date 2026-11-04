# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# oh-my-818's bash entry point: sourced by ~/.bashrc.
# Its folder, absolute (the code uses it after a cd), without forking
OM818_DIR="${BASH_SOURCE[0]%/*}"
if [[ "$OM818_DIR" == "${BASH_SOURCE[0]}" ]]; then OM818_DIR=.; fi
if [[ "$OM818_DIR" != /* ]]; then OM818_DIR="${PWD}/${OM818_DIR}"; fi

# The environment, when the startup files didn't load it (e.g. loaded through another file, or a
# plugin manager). om818_path_prepend comes from env.sh: defined means it is already loaded
_om818_env="${XDG_STATE_HOME:-${HOME}/.local/state}/om818/env.sh"
# (a temporary install's: only a folder of the user's, as modules/shell/init.sh checks it)
if [[ "${OM818_TEMP:-}" == /* && ! -L "$OM818_TEMP" && -O "$OM818_TEMP" ]]; then
  _om818_env="${OM818_TEMP}/state/env.sh"
fi
if ! declare -F om818_path_prepend >/dev/null && [[ -r "$_om818_env" ]]; then
  source -- "$_om818_env"
fi
unset _om818_env

source -- "${OM818_DIR}/modules/bash/init.bash"
