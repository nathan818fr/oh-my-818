# The prompt layer of the themes (modules/shell/themes), in zsh: prompt escapes, hooks and git
# status. Each function sets REPLY (_keys: reply), returns a status, or acts (_set, _hook, _defer,
# _redraw, _git_*), so the theme's code runs without forks.
# Internal: it may change with the themes.

zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS p:EPOCHREALTIME
zmodload -F zsh/parameter p:jobstates p:functions

# A color setting: words among bold, underline, reset and colors (a name like red, a 256-color
# number like 202, or #rrggbb), e.g. "bold 202"
function _om818_prompt_color() {
  local word out='' IFS=$' \t\n'
  for word in ${=1}; do
    case "$word" in
    reset) out+='%f%k%b%u%s' ;;
    bold) out+='%B' ;;
    underline) out+='%U' ;;
    *) out+="%F{${word}}" ;;
    esac
  done
  REPLY="$out"
}

# Plain text: % escaped, control characters (e.g. from a hostile directory or branch name, which
# could drive the terminal) replaced
function _om818_prompt_text() {
  REPLY="${1//[[:cntrl:]]/?}"
  REPLY="${REPLY//\%/%%}"
}

# A symbol: a single non-ASCII char is marked as one column wide (%{…%G%}), whatever the C
# library's width table says (a 0 or 2 there would shift the cursor)
function _om818_prompt_glyph() {
  if [[ "${#1}" -eq 1 && "$1" == [^[:ascii:]] ]]; then
    REPLY="%{${1}%G%}"
  else
    REPLY="${1//\%/%%}"
  fi
}

function _om818_prompt_user() {
  REPLY='%n'
}

# The account's name, as plain text
function _om818_prompt_username() {
  REPLY="$USERNAME"
}

# The current directory, with ~ for the home directory (zsh's %~ escapes control characters)
# usage: _om818_prompt_path [<folders shown: 0 for all> <ellipsis>]
function _om818_prompt_path() {
  local depth="${1:-0}"
  if [[ "$depth" -gt 0 ]]; then
    REPLY="%($((depth + 1))~|${2}/%${depth}~|%~)"
  else
    REPLY='%~'
  fi
}

# A date as plain text
# usage: _om818_prompt_date <strftime format> [<time zone>]
function _om818_prompt_date() {
  if [[ -n "${2:-}" ]]; then
    TZ="$2" builtin strftime -s REPLY "$1" "$EPOCHSECONDS"
  else
    builtin strftime -s REPLY "$1" "$EPOCHSECONDS"
  fi
}

# The name of a signal (2 -> INT), empty if unknown ($signals starts with EXIT, signal 0, at 1)
function _om818_prompt_signal() {
  REPLY="${signals[$1 + 1]:-}"
}

function _om818_prompt_jobs() {
  REPLY="${#jobstates}"
}

# usage: _om818_prompt_match <text> <glob pattern>
function _om818_prompt_match() {
  [[ "$1" == ${~2} ]]
}

function _om818_prompt_has_function() {
  [[ -n "${functions[$1]+x}" ]]
}

# Set reply to the keys of a table (an associative array's name)
function _om818_prompt_keys() {
  reply=("${(@kP)1}")
}

# The prompt. With prompt_subst on (set by many configs, e.g. oh-my-zsh's), PROMPT is expanded
# again before showing, so text from outside (a branch named `$(cmd)`) would run: PROMPT then
# only refers to the variable holding it, whose value isn't expanded again. Checked each time: the
# option may be set after the theme loads
function _om818_prompt_set() {
  typeset -g _om818_ps1="$1"
  if [[ -o prompt_subst ]]; then
    PROMPT='${_om818_ps1}'
  else
    PROMPT="$1"
  fi
}

# Redraw the prompt, from an async answer (gitstatus). Shown at once (zle -R): two reset-prompts
# without a refresh between them (two answers in one zle call) would each erase a line above it
function _om818_prompt_redraw() {
  if zle; then
    zle reset-prompt
    zle -R
  fi
}

# Run a function once the startup files are done and the prompt is shown. Without zsh-defer's
# precmd hooks and redraws (-mpr): they would run the prompt again over the first one, erasing
# the lines printed just before it (the update notice, a config typo)
function _om818_prompt_defer() {
  zsh-defer -mpr "$1"
}

# Put a function last in a hook array (precmd, preexec, chpwd), once
# usage: _om818_prompt_hook <hook> <function>
function _om818_prompt_hook() {
  local name="${1}_functions"
  local -a hooks=("${(@P)name}")
  hooks=("${(@)hooks:#${(b)2}}")
  set -A "$name" "${hooks[@]}" "$2"
}

### Git status (gitstatusd, async)

typeset -g _om818_prompt_git_cb='' _om818_prompt_git_timeout=0
typeset -gi _om818_prompt_git_started=0 _om818_prompt_git_inflight=0 _om818_prompt_git_requery=0

# Start gitstatusd (again, with these options: gitstatus_start's). Fails quietly: without it, the
# theme shows no git status (`om818 status` says why)
# usage: _om818_prompt_git_start <gitstatus_start options>...
function _om818_prompt_git_start() {
  gitstatus_stop om818 2>/dev/null
  _om818_prompt_git_started=0 _om818_prompt_git_inflight=0 _om818_prompt_git_requery=0
  # (a name of our own: other gitstatus users, e.g. powerlevel10k, don't clash)
  if gitstatus_start "$@" om818 2>/dev/null; then _om818_prompt_git_started=1; fi
}

# Query git status for $PWD, then run the callback with the VCS_STATUS_* variables (see
# gitstatus_query): at once if the answer comes within the timeout, else when it comes (the
# callback then redraws). Status 1 without gitstatusd (the callback doesn't run)
# usage: _om818_prompt_git_query <timeout> <callback>
function _om818_prompt_git_query() {
  if [[ "$_om818_prompt_git_started" -eq 0 ]]; then return 1; fi
  _om818_prompt_git_timeout="$1" _om818_prompt_git_cb="$2"
  # gitstatus forbids concurrent queries: redo this one when the pending one is done
  if [[ "$_om818_prompt_git_inflight" -eq 1 ]]; then
    _om818_prompt_git_requery=1
    return 0
  fi
  _om818_prompt_git_inflight=1
  if ! gitstatus_query -t "$1" -c _om818_prompt_git_answer om818; then
    _om818_prompt_git_inflight=0
    return 1
  fi
  if [[ "$VCS_STATUS_RESULT" == 'tout' ]]; then return 0; fi
  _om818_prompt_git_inflight=0
  "$2"
}

# Called by gitstatus with the answer to a query that timed out
function _om818_prompt_git_answer() {
  _om818_prompt_git_inflight=0
  if [[ "$_om818_prompt_git_requery" -eq 1 ]]; then
    _om818_prompt_git_requery=0
    _om818_prompt_git_query "$_om818_prompt_git_timeout" "$_om818_prompt_git_cb"
  else
    "$_om818_prompt_git_cb"
  fi
}
