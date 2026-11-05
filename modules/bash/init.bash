# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# The bash module: the environment and config (shared with zsh), each feature, the integrations
# and the prompt. Settings: defaults.sh, then ~/.config/om818/config.sh.

if [[ "$-" != *i* ]]; then return 0; fi
# bash 4.4+ (macOS ships 3.2): older ones get the environment only (`om818 status` says so)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ||
  ("${BASH_VERSINFO[0]}" -eq 4 && "${BASH_VERSINFO[1]}" -lt 4) ]]; then
  return 0
fi

# For the code shared with zsh
om818_shell=bash

# Set REPLY to the path of a command (status 1 if there is none). PATH is searched directly:
# `hash` skips names that are also functions (e.g. mise once activated). Windows' folders in WSL
# are skipped (slow, and no tool of ours is there)
function _om818_which() {
  # (split by hand: unquoted, it needs set -f, restored by `local -`, and when a function with it
  # returns, bash 4.4 starts recording what follows in the startup files in the user's history)
  local dir rest="${PATH}:"
  while [[ "$rest" == *:* ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    if [[ -n "${WSL_DISTRO_NAME:-}" && "$dir" == /mnt/[a-z]/* ]]; then continue; fi
    if [[ -n "$dir" && -f "${dir}/${1}" && -x "${dir}/${1}" ]]; then
      REPLY="${dir}/${1}"
      return 0
    fi
  done
  REPLY=''
  return 1
}

# Set REPLY to the current time, in seconds since the epoch
function _om818_now() {
  printf -v REPLY '%(%s)T' -1
}

source -- "${OM818_DIR}/modules/shell/init.sh"
if [[ "$OSTYPE" == darwin* ]] && shopt -q login_shell; then _om818_path_front; fi

# PROMPT_COMMAND as declared (one fork, also read by title.sh). Read-only (some servers, for audit
# logging), it leaves no way to run code at each prompt: no title, prompt or hooks then, quietly
# (bash-preexec would refuse to install, with errors)
_om818_pc="$(declare -p PROMPT_COMMAND 2>/dev/null)"
# (its attributes: "declare -ar PROMPT_COMMAND=…" gives "ar")
_om818_pc_attrs="${_om818_pc#declare -}"
_om818_pc_attrs="${_om818_pc_attrs%% *}"
if [[ "$_om818_pc_attrs" == *r* ]]; then
  # (and mise, direnv and zoxide, whose hooks need PROMPT_COMMAND; mise's shims stay on PATH, from
  # env.sh. modules/shell/integrations.sh reads these settings)
  # shellcheck disable=SC2034
  om818_title=off om818_theme=off om818_update=off om818_mise=off om818_direnv=off om818_zoxide=off
fi
# The title first: its PROMPT_COMMAND entry must come before bash-preexec's install entry,
# else bash 4.4-5.2 (preexec from a DEBUG trap) would take it for the first command, and miss
# the real one
if [[ "$om818_title" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/title.sh"; fi
# bash-preexec gives bash zsh's precmd_functions and preexec_functions, which the shared code uses
if [[ "$_om818_pc_attrs" != *r* ]]; then
  source -- "${OM818_DIR}/vendor/bash-preexec/bash-preexec.sh"
fi
unset _om818_pc _om818_pc_attrs

# Move a tool's hook from PROMPT_COMMAND to the front of precmd_functions: bash-preexec runs
# PROMPT_COMMAND after them, so after the prompt is made (e.g. direnv's environment one prompt
# late). Also when the user's own startup lines add it again later (it would run twice): checked
# at each prompt
# usage: _om818_precmd_first <function>
_om818_precmd_moved=()
function _om818_precmd_first() {
  if [[ " ${_om818_precmd_moved[*]} " != *" $1 "* ]]; then _om818_precmd_moved+=("$1"); fi
  _om818_hook_add precmd_functions _om818_precmd_keep_first
  _om818_precmd_keep_first
}
function _om818_precmd_keep_first() {
  local f
  for f in "${_om818_precmd_moved[@]}"; do
    if [[ "${PROMPT_COMMAND[*]:-}" != *"$f"* ]]; then continue; fi
    _om818_prompt_command_remove "$f"
    if [[ " ${precmd_functions[*]} " != *" $f "* ]]; then
      precmd_functions=("$f" "${precmd_functions[@]}")
    fi
  done
}

# Remove the entries <name> (whole commands, between ; or newlines: not my_name_log) from
# PROMPT_COMMAND, in its form, string or array (bash-preexec before 0.7 only handles a string)
# usage: _om818_prompt_command_remove <name>
function _om818_prompt_command_remove() {
  local i s old
  for i in "${!PROMPT_COMMAND[@]}"; do
    s=$'\n'"${PROMPT_COMMAND[i]}"$'\n'
    old=''
    # (also with blanks around ;, e.g. "history -a; _direnv_hook")
    while [[ "$s" != "$old" ]]; do
      old="$s"
      s="${s//$'\n'"$1"$'\n'/$'\n'}"
      s="${s//$'\n'"$1";/$'\n'}"
      s="${s//$'\n'"$1" ;/$'\n'}"
      s="${s//;"$1"$'\n'/$'\n'}"
      s="${s//; "$1"$'\n'/$'\n'}"
      s="${s//;"$1";/;}"
      s="${s//; "$1";/;}"
      s="${s//;"$1" ;/;}"
      s="${s//; "$1" ;/;}"
    done
    s="${s#$'\n'}"
    s="${s%$'\n'}"
    # shellcheck disable=SC2090,SC2178 # (a string or an array)
    if [[ "$(declare -p PROMPT_COMMAND)" != 'declare -a'* ]]; then
      PROMPT_COMMAND="$s"
    elif [[ -z "${s//[;[:space:]]/}" ]]; then
      unset 'PROMPT_COMMAND[i]'
    else
      PROMPT_COMMAND[i]="$s"
    fi
  done
}

# A command starting with a space stays out of the history (om818_history, or the user's
# HISTCONTROL): bash-preexec drops ignorespace, as it reads the command from the history. So the
# entry is deleted as the command starts, if it is the last one (not with HISTCMD: its meaning
# changed in bash 5.1)
function _om818_history_ignorespace() {
  local last text cmd
  if [[ "$1" != [[:space:]]* ]]; then return 0; fi
  if [[ "$om818_history" == 'off' && -z "${_om818_ignorespace:-}" ]]; then return 0; fi
  # ("  <number>[*]  <command>": a fork, only for such a command; compared without the leading
  # spaces)
  last="$(HISTTIMEFORMAT='' builtin history 1)"
  last="${last#"${last%%[![:space:]]*}"}"
  text="${last#"${last%%[!0-9]*}"}"
  text="${text#\*}"
  text="${text#"${text%%[![:space:]]*}"}"
  cmd="${1%%$'\n'*}"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  if [[ -n "$cmd" && "$text" == "$cmd"* ]]; then builtin history -d "${last%%[!0-9]*}"; fi
}
_om818_hook_add preexec_functions _om818_history_ignorespace
# With om818_history=off, the user's HISTCONTROL decides whether a leading space hides a command.
# bash-preexec removes ignorespace at its install (the first prompt, after all startup lines), so
# its function is wrapped to note it first (one fork; once: a reload would wrap the wrapper)
if [[ "$om818_history" == 'off' ]] && declare -F __bp_adjust_histcontrol >/dev/null &&
  ! declare -F _om818_bp_adjust_histcontrol >/dev/null; then
  _om818_f="$(declare -f __bp_adjust_histcontrol)"
  eval "function _om818_bp_adjust_histcontrol ${_om818_f#*$'\n'}"
  unset _om818_f
  function __bp_adjust_histcontrol() {
    if [[ "${HISTCONTROL:-}" == *ignorespace* || "${HISTCONTROL:-}" == *ignoreboth* ]]; then
      _om818_ignorespace=1
    fi
    _om818_bp_adjust_histcontrol
  }
fi

if [[ "$om818_history" != 'off' ]]; then source -- "${OM818_DIR}/modules/bash/history.bash"; fi
if [[ "$om818_keys" != 'off' ]]; then source -- "${OM818_DIR}/modules/bash/keys.bash"; fi
if [[ "$om818_completion" != 'off' ]]; then
  source -- "${OM818_DIR}/modules/bash/completion.bash"
fi
if [[ "$om818_clipboard" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/clipboard.sh"; fi
# No terminal bell (e.g. on an empty completion), as in zsh; only with line editing (not in
# `bash -i -c` without a terminal)
if [[ -o emacs || -o vi ]]; then bind 'set bell-style none'; fi

source -- "${OM818_DIR}/modules/shell/integrations.sh"
if [[ "$om818_theme" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/prompt.sh"; fi
if [[ "$om818_update" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/update.sh"; fi

# bash-preexec before 0.7, loaded first by the user, handles only a string PROMPT_COMMAND: one made
# an array meanwhile (e.g. by a tool's hook, Fedora's profile) is joined back into one string, its
# install lines last (an entry after them would take the first command's turn). A read-only array
# (declare -ar) is left as is. The fork runs only when such a bash-preexec is loaded
if [[ -n "${bash_preexec_imported:-}${__bp_imported:-}" ]] &&
  ! declare -F __bp_use_array_prompt_command >/dev/null &&
  [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == 'declare -a '* ]]; then
  _om818_pc="$(IFS=$'\n' && printf '%s' "${PROMPT_COMMAND[*]}")"
  # shellcheck disable=SC2016 # its lines, as is
  _om818_bp=$'__bp_trap_string="$(trap -p DEBUG)"\ntrap - DEBUG\n__bp_install'
  if [[ "$_om818_pc" == *"$_om818_bp"$'\n'* ]]; then
    _om818_pc="${_om818_pc/"$_om818_bp"$'\n'/}"$'\n'"$_om818_bp"
  fi
  unset _om818_bp
  unset PROMPT_COMMAND
  # shellcheck disable=SC2178 # an array made a string again
  PROMPT_COMMAND="$_om818_pc"
  unset _om818_pc
fi

# Only needed while starting
unset -f _om818_which _om818_cached _om818_now _om818_files_of _om818_same_time _om818_stamp
unset REPLY
_om818_loaded=1
