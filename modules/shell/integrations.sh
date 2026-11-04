# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# The interactive part of the integrations, then the user's shell.d files (code valid in zsh and
# bash). Which integrations are on comes from the generated environment (om818_integrations:
# name:tool pairs, mise first); here, only whether the tool is installed is checked (tools come
# and go, e.g. with mise), and the setting again: config.sh may turn one off in one shell only.
# Each one's interactive.<shell> is sourced, else its interactive.sh.

# Set REPLY to a binary's path, its links resolved: Nix and Guix profiles link into a store whose
# files all have the same time, so only the path tells an upgraded binary apart. (bash: only a
# link itself, as a fork would cost each start)
function _om818_resolved() {
  REPLY="$1"
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    REPLY="${1:A}"
  elif [[ -L "$1" ]]; then
    REPLY="$(readlink -f -- "$1" 2>/dev/null)" || REPLY=''
    if [[ -z "$REPLY" ]]; then REPLY="$1"; fi
  fi
}

# Set REPLY to a file holding a command's output, for tools' init scripts that don't depend on the
# environment (fzf, direnv hook). The file is made again when the command's binary changes: another
# path, links resolved (its first line), or another modification time (the file gets the binary's,
# since packages keep their build time: an upgraded binary can be older than the file). A failure
# (its error in <file>.failed, which `om818 status` shows) is not retried, quietly, until the binary
# changes.
function _om818_cached() {
  local bin file line name="$*"
  REPLY=''
  if ! _om818_which "$1"; then return 1; fi
  _om818_resolved "$REPLY"
  bin="$REPLY"
  REPLY=''
  file="${_om818_cache_dir}/eval/${om818_shell}-${name//[^A-Za-z0-9.-]/-}"
  if [[ -s "$file" ]] && _om818_same_time "$bin" "$file" && IFS= read -r line <"$file" &&
    [[ "$line" == "# om818: ${bin}" ]]; then
    REPLY="$file"
    return 0
  fi
  if [[ -e "${file}.failed" ]] && _om818_same_time "$bin" "${file}.failed"; then return 1; fi
  mkdir -p -- "${file%/*}" || return 1
  # ($$: each shell has its own temporary files; in /: the tool may read the folder's config)
  if { printf '# om818: %s\n' "$bin" && (cd / && "$@"); } >|"${file}.tmp.$$" \
    2>|"${file}.failed.tmp.$$"; then
    _om818_stamp "$bin" "${file}.tmp.$$" "$file"
    mv -f -- "${file}.tmp.$$" "$file"
    rm -f -- "${file}.failed.tmp.$$" "${file}.failed"
    REPLY="$file"
  else
    _om818_stamp "$bin" "${file}.failed.tmp.$$" "${file}.failed"
    mv -f -- "${file}.failed.tmp.$$" "${file}.failed"
    rm -f -- "${file}.tmp.$$"
    return 1
  fi
}

# Whether a cached file (2) still matches the binary (1): the same modification time; for one
# whose time couldn't be copied exactly (old busybox's touch -r keeps whole seconds: its mark,
# <file>.coarse, holding the binary's `ls -lnL` line), not older than it, and the same listing
function _om818_same_time() {
  [[ ! "$1" -nt "$2" && ! "$1" -ot "$2" ]] && return 0
  [[ -e "${2}.coarse" && ! "$1" -nt "$2" &&
    "$(command ls -lnL -- "$1" 2>/dev/null)" == "$(<"${2}.coarse")" ]]
}

# Give a cached file (2) the binary's (1) modification time; where it can't be copied exactly, the
# current time, and its mark for _om818_same_time
# usage: _om818_stamp <binary> <file> [<final name of the file>]
function _om818_stamp() {
  touch -r "$1" -- "$2"
  if [[ "$1" -nt "$2" ]]; then
    touch -- "$2"
    command ls -lnL -- "$1" >|"${3:-$2}.coarse" 2>/dev/null
  else
    rm -f -- "${3:-$2}.coarse"
  fi
}

# Set _om818_files to the files of a directory for this shell (*.sh and *.<shell>), in name order
function _om818_files_of() {
  local f failglob=0
  # (bash's failglob, some users' option, would make an empty folder an error)
  if [[ "$om818_shell" == 'zsh' ]]; then
    setopt local_options null_glob
  elif shopt -q failglob; then
    failglob=1
    shopt -u failglob
  fi
  _om818_files=()
  for f in "$1"/*; do
    case "$f" in
    *.sh | *."$om818_shell") if [[ -f "$f" ]]; then _om818_files+=("$f"); fi ;;
    esac
  done
  if [[ "$failglob" -eq 1 ]]; then shopt -s failglob; fi
}

# Put the folders of om818_path_first back first on PATH, in their order (out: only take them out)
function _om818_path_first() {
  local dir rest="${OM818_PATH_FIRST:-}:"
  while [[ "$rest" == *:* ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    if [[ -z "$dir" ]]; then continue; fi
    om818_path_remove "$dir"
    if [[ "$1" == 'in' ]]; then PATH="${dir}${PATH:+:${PATH}}"; fi
  done
}

# The folders of om818_path_first leave PATH during the integrations, then come back first, in
# front of what they added. Re-adding them after isn't enough: mise puts its tools in front of the
# PATH it was activated with, but keeps in front what is added after
_om818_path_first out

_om818_rest="${om818_integrations:-} "
while [[ "$_om818_rest" == *' '* ]]; do
  _om818_name="${_om818_rest%% *}"
  _om818_rest="${_om818_rest#* }"
  if [[ -z "$_om818_name" ]]; then continue; fi
  _om818_tool="${_om818_name##*:}"
  _om818_name="${_om818_name%%:*}"
  eval "_om818_mode=\"\${om818_${_om818_name}:-}\""
  if [[ "$_om818_mode" == 'off' ]]; then continue; fi
  if [[ -n "$_om818_tool" ]] && ! _om818_which "$_om818_tool"; then continue; fi
  _om818_file="${OM818_DIR}/integrations/${_om818_name}/interactive"
  if [[ -r "${_om818_file}.${om818_shell}" ]]; then
    source -- "${_om818_file}.${om818_shell}"
  elif [[ -r "${_om818_file}.sh" ]]; then
    source -- "${_om818_file}.sh"
  fi
done

_om818_path_first in

# The user's interactive layer
_om818_files_of "${_om818_config_dir}/shell.d"
for _om818_file in "${_om818_files[@]}"; do
  source -- "$_om818_file"
done
unset _om818_name _om818_rest _om818_tool _om818_mode _om818_file _om818_files

# Before each prompt, the folders of om818_path_first go back first if something went in front
# (direnv, a virtualenv's activate, a shell.d file): only a string comparison when nothing did
function _om818_path_first_keep() {
  local dir rest="${OM818_PATH_FIRST:-}:" prefix=''
  if [[ -z "${OM818_PATH_FIRST:-}" ]]; then return 0; fi
  # They are first in the reverse order of OM818_PATH_FIRST (each one went in front)
  while [[ "$rest" == *:* ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    if [[ -n "$dir" ]]; then prefix="${dir}:${prefix}"; fi
  done
  if [[ "${PATH}:" != "$prefix"* ]]; then _om818_path_first in; fi
}
_om818_hook_add precmd_functions _om818_path_first_keep
