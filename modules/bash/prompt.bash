# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# The prompt layer of the themes (modules/shell/themes), in bash: prompt escapes, hooks and git
# status (internal: it may change with the themes). Each function sets REPLY (_keys: reply),
# returns a status, or acts (_set, _hook, _defer, _redraw, _git_*). PS1 only refers to a variable
# holding the prompt: bash inserts its value as is (no escapes or expansions to protect), with
# \001 and \002 around what takes no columns.

# The account's name (\u: not $USER, which can differ), once
_om818_user='\u'
_om818_user="${_om818_user@P}"

# A color setting: words among bold, underline, reset and colors (a name like red, a 256-color
# number like 202, or #rrggbb), e.g. "bold 202"
function _om818_prompt_color() {
  local word out='' code IFS=$' \t\n'
  for word in $1; do
    case "$word" in
    reset) code='0' ;;
    bold) code='1' ;;
    underline) code='4' ;;
    # The 8 named colors and 0-15 as basic codes: the only ones the Linux console knows
    black) code='30' ;;
    red) code='31' ;;
    green) code='32' ;;
    yellow) code='33' ;;
    blue) code='34' ;;
    magenta) code='35' ;;
    cyan) code='36' ;;
    white) code='37' ;;
    default) code='39' ;;
    [0-7]) code="3${word}" ;;
    8 | 9 | 1[0-5]) code="9$((word - 8))" ;;
    \#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
      code="38;2;$((16#${word:1:2}));$((16#${word:3:2}));$((16#${word:5:2}))"
      ;;
    *[!0-9]* | '') continue ;;
    *) code="38;5;${word}" ;;
    esac
    out+=$'\001\e['"${code}"$'m\002'
  done
  REPLY="$out"
}

# Plain text: control characters (e.g. from a hostile directory or branch name, which could drive
# the terminal) replaced; nothing else to escape (see the header)
function _om818_prompt_text() {
  REPLY="${1//[[:cntrl:]]/?}"
}

# A symbol (bash can't set its width: it uses the C library's)
function _om818_prompt_glyph() {
  REPLY="$1"
}

function _om818_prompt_user() {
  REPLY="$_om818_user"
}

# The account's name, as plain text
function _om818_prompt_username() {
  REPLY="$_om818_user"
}

# The current directory, with ~ for the home directory
# usage: _om818_prompt_path [<folders shown: 0 for all> <ellipsis>]
function _om818_prompt_path() {
  local depth="${1:-0}" path="${PWD//[[:cntrl:]]/?}" IFS=/
  local -a parts
  if [[ "$path" == "$HOME" || "$path" == "$HOME"/* ]]; then path="~${path#"$HOME"}"; fi
  REPLY="$path"
  if [[ "$depth" -le 0 ]]; then return 0; fi
  # Like zsh's %(N~…): the folders of the path (~ counts as one, / doesn't), the last ones shown
  read -ra parts <<<"${path#/}"
  if [[ "${#parts[@]}" -le "$depth" ]]; then return 0; fi
  REPLY="${2}/${parts[*]: -depth}"
}

# A date as plain text
# usage: _om818_prompt_date <strftime format> [<time zone>]
function _om818_prompt_date() {
  if [[ -n "${2:-}" ]]; then
    TZ="$2" printf -v REPLY "%(${1})T" -1
  else
    printf -v REPLY "%(${1})T" -1
  fi
}

# The name of a signal (2 -> INT), empty if unknown (forks: only after a command killed by one)
function _om818_prompt_signal() {
  REPLY="$(kill -l "$1" 2>/dev/null)" || REPLY=''
}

# The running and stopped jobs (forks: bash can't count them otherwise; its \j also counts the
# finished jobs it hasn't reported yet)
function _om818_prompt_jobs() {
  local pids
  pids="$(jobs -pr && jobs -ps)"
  REPLY=0
  if [[ -n "$pids" ]]; then
    pids="${pids//[!$'\n']/}"
    REPLY="$((${#pids} + 1))"
  fi
}

# usage: _om818_prompt_match <text> <glob pattern>
function _om818_prompt_match() {
  # shellcheck disable=SC2053 # a pattern on purpose
  [[ "$1" == $2 ]]
}

function _om818_prompt_has_function() {
  declare -F "$1" >/dev/null
}

# Set reply to the keys of a table (an associative array's name)
function _om818_prompt_keys() {
  eval "reply=(\"\${!${1}[@]}\")"
}

function _om818_prompt_set() {
  _om818_ps1="$1"
  # shellcheck disable=SC2016 # expanded by bash when showing the prompt
  # (promptvars, on by default, expands it: a user may have turned it off)
  shopt -s promptvars
  PS1='${_om818_ps1}'
}

# Redraw the prompt: bash can't, so the theme waits for git instead
function _om818_prompt_redraw() {
  :
}

# Run a function at the first prompt, once the startup files are done
function _om818_prompt_defer() {
  _om818_deferred+=("$1")
}

_om818_deferred=()
function _om818_run_deferred() {
  local f
  for f in "${_om818_deferred[@]}"; do "$f"; done
  _om818_deferred=()
  _om818_prompt_unhook precmd _om818_run_deferred
  # bash-preexec lists `precmd` and `preexec` in its hooks in case they get defined: it looks each
  # up at every prompt and command (`type -t`: through all of PATH when there is no such function)
  for f in precmd preexec; do
    if ! declare -F "$f" >/dev/null; then _om818_prompt_unhook "$f" "$f"; fi
  done
}
# First, before the hooks that the deferred functions reorder
if [[ " ${precmd_functions[*]} " != *' _om818_run_deferred '* ]]; then
  precmd_functions=(_om818_run_deferred "${precmd_functions[@]}")
fi

# Put a function last in a hook array (precmd, preexec; bash has no chpwd), once
# usage: _om818_prompt_hook <hook> <function>
function _om818_prompt_hook() {
  if [[ "$1" == 'chpwd' ]]; then return 0; fi
  _om818_prompt_unhook "$1" "$2"
  local -n _hooks="${1}_functions"
  _hooks+=("$2")
}

# Remove a function from a hook array
# usage: _om818_prompt_unhook <hook> <function>
function _om818_prompt_unhook() {
  local f
  local -a kept=()
  # shellcheck disable=SC2178 # a reference to an array
  local -n _hooks="${1}_functions"
  for f in "${_hooks[@]}"; do
    if [[ "$f" != "$2" ]]; then kept+=("$f"); fi
  done
  _hooks=("${kept[@]}")
}

### Git status (gitstatusd: bash waits for it, it can't redraw)

_om818_prompt_git_started=0

# Start gitstatusd (again, with these options: gitstatus_start's). Fails quietly: without it, the
# theme shows no git status (`om818 status` says why)
# usage: _om818_prompt_git_start <gitstatus_start options>...
function _om818_prompt_git_start() {
  local pipe_trap
  # (gitstatus's code fails with set -u, which some users have in their .bashrc)
  local -
  set +u
  gitstatus_stop 2>/dev/null
  _om818_prompt_git_started=0
  # gitstatus_start writes to the daemon it started: when the daemon exits at once (not
  # downloaded, or failing), SIGPIPE kills the shell. So not without it, and SIGPIPE ignored
  if [[ -z "${GITSTATUS_DAEMON:-}" ]] &&
    ! compgen -G "${GITSTATUS_CACHE_DIR}/gitstatusd-*" >/dev/null; then
    return 0
  fi
  pipe_trap="$(trap -p PIPE)"
  trap '' PIPE
  if gitstatus_start "$@" 2>/dev/null; then _om818_prompt_git_started=1; fi
  eval "${pipe_trap:-trap - PIPE}"
}

# Query git status for $PWD, then run the callback with the VCS_STATUS_* variables (see
# gitstatus_query); past the timeout, with VCS_STATUS_RESULT=tout. Status 1 without gitstatusd
# usage: _om818_prompt_git_query <timeout> <callback>
function _om818_prompt_git_query() {
  local -
  if [[ "$_om818_prompt_git_started" -eq 0 ]]; then return 1; fi
  set +u
  # The daemon may have died since (a crash, the OOM killer): writing to it would raise SIGPIPE,
  # which kills the shell. Ignored meanwhile, then the user's PIPE trap back: the one set when
  # the first prompt came (read once: a fork). A dead daemon is stopped: no git status from then on
  if [[ -z "${_om818_pipe_trap+set}" ]]; then _om818_pipe_trap="$(trap -p PIPE)"; fi
  trap '' PIPE
  # (-d: else it forks for `pwd -P`; without effect when GIT_DIR is set)
  # shellcheck disable=SC2034 # read by the callback
  if ! gitstatus_query -t "$1" -d "$PWD" 2>/dev/null; then
    VCS_STATUS_RESULT='error'
    if [[ -z "${GITSTATUS_DAEMON_PID:-}" ]] || ! kill -0 "$GITSTATUS_DAEMON_PID" 2>/dev/null; then
      gitstatus_stop 2>/dev/null
      _om818_prompt_git_started=0
    fi
  fi
  eval "${_om818_pipe_trap:-trap - PIPE}"
  "$2"
}
