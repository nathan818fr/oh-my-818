# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# om818-classic: two-line prompt, with git status from gitstatus (zsh and bash):
#   ✔ 3s (drop:dev venv:api) user ~/path [branch↑1≡1|●1✚2…3] {todo}
#   12:34 ⚙1 $
# Code valid in zsh and bash: it only builds text, through the prompt layer of the shell's module
# (modules/<shell>/prompt.*: _om818_prompt_color, _text, _glyph, _user, _username, _path, _date,
# _signal, _jobs, _match, _has_function, _keys, _set, _redraw, _defer, _hook, _git_start,
# _git_query). That layer is internal (it may change): what is public is the settings and the
# indicators.
#
# Settings are the om818_prompt_* (with their defaults in defaults.sh). They are read when the
# theme loads: after changing one in a running shell, start a new shell.
#
# Each line is a list of segments, shown in order, separated by a space ("+name": no space before
# it), and skipped when empty. Segments: status duration env user path git indicators date jobs
# symbol. Leave a segment out to turn it off, e.g. no clock and no git:
#   om818_prompt_line1=(status duration env user path indicators)
#   om818_prompt_line2=(jobs symbol)
#
# Indicators are short flags added from outside the theme, shown by the indicators segment in the
# order of om818_prompt_indicators. An indicator is an om818_indicator_<name> function that sets
# REPLY to plain text (empty: hidden); its color is om818_prompt_indicator_colors[<name>], else
# om818_prompt_colors[indicator]. Define it in a shell.d file, e.g. shell.d/todo.sh:
#   function om818_indicator_todo() { if [[ -e ~/TODO ]]; then REPLY='todo'; fi }
#   om818_prompt_indicators+=(todo)
#
# A segment is a prompt_om818-classic_segment_<name> function setting REPLY to its prompt text
# (git is set by its query instead); it runs in the precmd hook and sees its locals (pst, ran,
# secs). An environment is a prompt_om818-classic_env_<name> function. New ones go in the lists of
# defaults.sh, this header and docs/prompt.md; new table keys in color_keys/symbol_keys and
# defaults.sh's tables.

function prompt_om818-classic_setup() {
  local name basic=0 glyph='✔' REPLY
  local -a reply
  # The keys of the color and symbol tables this theme uses
  local -a color_keys=(
    user host root path date ok err env duration jobs indicator indicator_bracket
    env_drop env_container env_chroot env_ssh env_flatpak env_nix env_flox env_venv env_conda
    git_bracket git_branch git_action git_remote git_no_upstream git_staged git_conflicts
    git_changed git_untracked git_stashes git_unknown git_clean
  )
  local -a symbol_keys=(
    user root host_separator ok err jobs env_prefix env_suffix env_separator path_ellipsis
    indicator_prefix indicator_suffix
    git_prefix git_suffix git_separator git_behind git_ahead git_push_behind git_push_ahead
    git_no_upstream git_staged git_conflicts git_changed git_untracked git_stashes git_unknown
    git_clean
  )

  # Basic mode, for terminals with few colors or no Unicode: the *_basic tables (a key they don't
  # have: the main table's). On, off or auto: the Linux console and other basic terminals, or a
  # locale that isn't UTF-8. The locale the shell really got: one named in LANG may not exist
  # (e.g. sent by an SSH client), then the shell runs in the C locale, where ✔ is 3 chars long
  if [[ "$om818_prompt_basic" == 'on' || ("$om818_prompt_basic" == 'auto' &&
    ("$TERM" == linux || "$TERM" == dumb || "$TERM" == vt* || "${#glyph}" -ne 1)) ]]; then
    basic=1
  fi
  prompt_om818-classic_check_keys om818_prompt_colors color_keys
  prompt_om818-classic_check_keys om818_prompt_colors_basic color_keys
  prompt_om818-classic_check_keys om818_prompt_symbols symbol_keys
  prompt_om818-classic_check_keys om818_prompt_symbols_basic symbol_keys

  # Seconds to wait for git status. zsh shows the prompt without it past that, and redraws it when
  # it comes; bash can't redraw, so it waits longer
  typeset -g _om818_classic_git_timeout="$om818_prompt_git_timeout"
  if [[ -z "$_om818_classic_git_timeout" ]]; then
    _om818_classic_git_timeout=0.02
    if [[ "$om818_shell" == 'bash' ]]; then _om818_classic_git_timeout=0.5; fi
  fi

  # Prompt strings of the colors and symbols (c, s), made once
  typeset -gA _om818_classic_c=() _om818_classic_s=()
  for name in "${color_keys[@]}"; do
    prompt_om818-classic_lookup om818_prompt_colors "$name" "$basic"
    _om818_prompt_color "$REPLY"
    _om818_classic_c[$name]="$REPLY"
  done
  for name in "${symbol_keys[@]}"; do
    prompt_om818-classic_lookup om818_prompt_symbols "$name" "$basic"
    _om818_prompt_glyph "$REPLY"
    _om818_classic_s[$name]="$REPLY"
  done
  _om818_prompt_color reset
  typeset -g _om818_classic_reset="$REPLY"

  # The segments, environments and git-ignored directories to use: checked once here, not at
  # each prompt
  typeset -gA _om818_classic_segments=()
  typeset -ga _om818_classic_envs=() _om818_classic_git_ignore=()
  typeset -g _om818_classic_shows_git=0
  for name in "${om818_prompt_line1[@]}" "${om818_prompt_line2[@]}"; do
    name="${name#+}"
    if [[ "$name" == 'git' ]]; then
      # (om818_prompt_git=off: no gitstatus, so nothing to show)
      if [[ "$om818_prompt_git" != 'off' ]]; then _om818_classic_shows_git=1; fi
    elif _om818_prompt_has_function "prompt_om818-classic_segment_${name}"; then
      _om818_classic_segments[$name]=1
    else
      printf 'oh-my-818: unknown prompt segment: %s (om818_prompt_line1/2; see defaults.sh)\n' \
        "$name" >&2
    fi
  done
  for name in "${om818_prompt_envs[@]}"; do
    if _om818_prompt_has_function "prompt_om818-classic_env_${name}"; then
      _om818_classic_envs+=("$name")
    else
      printf 'oh-my-818: unknown prompt environment: %s (om818_prompt_envs; see defaults.sh)\n' \
        "$name" >&2
    fi
  done
  for name in "${om818_prompt_git_ignore[@]}"; do
    # ~/ in a quoted pattern (zsh would expand it, bash not)
    # shellcheck disable=SC2088 # that ~
    if [[ "$name" == '~/'* ]]; then name="${HOME}/${name#'~/'}"; fi
    _om818_classic_git_ignore+=("$name")
  done

  # State: the text of each segment, the directory of the git segment, the running command's
  # start time (microseconds), the last background job ($!), and what doesn't change: the
  # container we are in
  typeset -gA _om818_classic_parts=()
  typeset -g _om818_classic_git_pwd='' _om818_classic_cmd_start='' _om818_classic_container=''
  typeset -g _om818_classic_last_bg="${!:-}" _om818_classic_indicators_checked=0
  REPLY=''
  prompt_om818-classic_container
  _om818_classic_container="$REPLY"

  _om818_prompt_hook preexec prompt_om818-classic_preexec
  _om818_prompt_hook precmd prompt_om818-classic_precmd
  _om818_prompt_hook chpwd prompt_om818-classic_chpwd
  _om818_prompt_defer prompt_om818-classic_late_init
}

# What must wait until the startup files have loaded: our hooks run after those they add (mise's,
# direnv's can change the environments we show: recomputed, and redrawn when they changed), and
# gitstatusd starts (zsh: once the first prompt is shown; bash: just before it)
function prompt_om818-classic_late_init() {
  local before="${_om818_classic_parts[env]-}${_om818_classic_parts[indicators]-}"
  _om818_prompt_hook precmd prompt_om818-classic_precmd
  _om818_prompt_hook chpwd prompt_om818-classic_chpwd
  prompt_om818-classic_compute env
  prompt_om818-classic_compute indicators
  if [[ "${_om818_classic_parts[env]-}${_om818_classic_parts[indicators]-}" != "$before" ]]; then
    prompt_om818-classic_render
    _om818_prompt_redraw
  fi
  if [[ "$_om818_classic_shows_git" -eq 1 ]]; then prompt_om818-classic_git_start; fi
}

# Indicators named but not defined (a typo): said once, at the first prompt, when the startup files
# have defined them (shell.d, the rc file)
function prompt_om818-classic_check_indicators() {
  local name
  _om818_classic_indicators_checked=1
  for name in "${om818_prompt_indicators[@]}"; do
    if ! _om818_prompt_has_function "om818_indicator_${name}"; then
      printf 'oh-my-818: prompt indicator %s has no om818_indicator_%s function\n' \
        "$name" "$name" >&2
    fi
  done
}

# Set REPLY to a key of a table (its name): from its _basic twin in basic mode, when that has it
# usage: prompt_om818-classic_lookup <table> <key> <basic: 0 or 1>
function prompt_om818-classic_lookup() {
  if [[ "$3" -eq 1 ]]; then
    eval "if [[ -n \"\${${1}_basic[\$2]+x}\" ]]; then REPLY=\"\${${1}_basic[\$2]}\"; return 0; fi"
  fi
  eval "REPLY=\"\${${1}[\$2]-}\""
}

# Warn about the keys of a table that the theme doesn't use (likely a typo)
# usage: prompt_om818-classic_check_keys <table> <array of the known keys>
function prompt_om818-classic_check_keys() {
  local key known IFS=' '
  local -a reply
  _om818_prompt_keys "$1"
  eval "known=\" \${${2}[*]} \""
  for key in "${reply[@]}"; do
    if [[ "$known" != *" ${key} "* ]]; then
      printf 'oh-my-818: unknown key in %s: %s (a typo? see defaults.sh)\n' "$1" "$key" >&2
    fi
  done
}

# Set REPLY to the kind and name of the container we are in, if any: podman (toolbox, distrobox),
# docker, or one that says so in $container (systemd-nspawn, LXC)
function prompt_om818-classic_container() {
  if [[ -f /.dockerenv ]]; then
    REPLY='docker'
    return 0
  fi
  if [[ ! -f /run/.containerenv ]]; then
    if [[ -n "${container:-}" ]]; then REPLY="$container"; fi
    return 0
  fi
  local kind='container' name='' line
  if [[ -f /run/.toolboxenv ]]; then
    kind='toolbox'
  elif [[ -n "${CONTAINER_ID:-}" ]]; then
    kind='distrobox'
  fi
  while IFS= read -r line; do
    if [[ "$line" == name=* ]]; then
      name="${line#name=}"
      name="${name//\"/}"
    fi
  done </run/.containerenv
  REPLY="${kind}:${CONTAINER_ID:-$name}"
}

function prompt_om818-classic_preexec() {
  local REPLY
  prompt_om818-classic_now
  _om818_classic_cmd_start="$REPLY"
}

function prompt_om818-classic_precmd() {
  # The last pipeline's statuses, first: zsh's $pipestatus. bash has none, and bash-preexec has
  # already reset PIPESTATUS: it keeps a copy (BP_PIPESTATUS). Neither is updated by a command
  # started in the background (`sleep 9 &`, which changes $!): then $?, its status, alone
  # (both in one statement: any command resets them; ${a[@]:0:1} is the first item in both shells)
  local -a pst=("$?" "${pipestatus[@]}")
  local last="${pst[*]:0:1}"
  pst=("${pst[@]:1}")
  if [[ "${#pst[@]}" -eq 0 ]]; then
    pst=("${BP_PIPESTATUS[@]}")
    if [[ "${pst[${#pst[@]} - 1]}" != "${__bp_last_ret_value:-0}" ]]; then
      pst=("${__bp_last_ret_value:-0}")
    fi
  fi
  if [[ "${!:-}" != "$_om818_classic_last_bg" ]]; then
    _om818_classic_last_bg="${!:-}"
    pst=("$last")
  fi
  if [[ "$_om818_classic_indicators_checked" -eq 0 ]]; then
    prompt_om818-classic_check_indicators
  fi
  # Not "name": segments see this function's locals, and env reads nix's $name
  local segment REPLY

  # Whether a command ran since the last prompt (not just an empty command line), and how long
  local ran=0 secs=0
  if [[ -n "$_om818_classic_cmd_start" ]]; then
    ran=1
    prompt_om818-classic_now
    if [[ -n "$REPLY" && "$_om818_classic_cmd_start" != '-' ]]; then
      secs="$(((REPLY - _om818_classic_cmd_start) / 1000000))"
    fi
    _om818_classic_cmd_start=''
  fi

  for segment in "${om818_prompt_line1[@]}" "${om818_prompt_line2[@]}"; do
    prompt_om818-classic_compute "${segment#+}"
  done
  prompt_om818-classic_git_query
  prompt_om818-classic_render
}

# zsh: a cd from a widget (e.g. fzf's Alt-C) redraws the prompt without running precmd: refresh
# the segments that depend on the directory (outside widgets, precmd comes next and does it)
function prompt_om818-classic_chpwd() {
  if ! zle; then return 0; fi
  prompt_om818-classic_compute env
  prompt_om818-classic_git_query
  prompt_om818-classic_render
  _om818_prompt_redraw
}

# Set a segment from its function (git is set by its query instead)
function prompt_om818-classic_compute() {
  if [[ -z "${_om818_classic_segments[$1]:-}" ]]; then return 0; fi
  local REPLY=''
  "prompt_om818-classic_segment_${1}"
  _om818_classic_parts[$1]="$REPLY"
}

function prompt_om818-classic_render() {
  local REPLY line1 line2
  prompt_om818-classic_join om818_prompt_line1
  line1="$REPLY"
  prompt_om818-classic_join om818_prompt_line2
  line2="$REPLY"
  if [[ -n "$line1" && -n "$line2" ]]; then
    _om818_prompt_set "${line1}"$'\n'"${line2} "
  else
    _om818_prompt_set "${line1}${line2} "
  fi
}

# Set REPLY to the non-empty segments of a line (the name of its array), separated by a space
function prompt_om818-classic_join() {
  local name text out=''
  eval "local -a names=(\"\${${1}[@]}\")"
  for name in "${names[@]}"; do
    text="${_om818_classic_parts[${name#+}]:-}"
    if [[ -z "$text" ]]; then continue; fi
    if [[ -n "$out" && "$name" != +* ]]; then out+=' '; fi
    out+="$text"
  done
  REPLY="$out"
}

### Segments

# The environments we are in, in the order of om818_prompt_envs (see the prompt_om818-classic_env_*
# functions below), each in its color (om818_prompt_colors[env_<name>], else [env])
function prompt_om818-classic_segment_env() {
  local env shown='' color
  for env in "${_om818_classic_envs[@]}"; do
    REPLY=''
    "prompt_om818-classic_env_${env}"
    if [[ -z "$REPLY" ]]; then continue; fi
    _om818_prompt_text "$REPLY"
    color="${_om818_classic_c[env_${env}]:-${_om818_classic_c[env]}}"
    shown+="${shown:+${_om818_classic_s[env_separator]}}${color}${REPLY}${_om818_classic_reset}"
  done
  REPLY=''
  if [[ -n "$shown" ]]; then
    REPLY="${_om818_classic_c[env]}${_om818_classic_s[env_prefix]}${_om818_classic_reset}${shown}"
    REPLY+="${_om818_classic_c[env]}${_om818_classic_s[env_suffix]}${_om818_classic_reset}"
  fi
}

### Environments: each sets REPLY to "kind:name" (or "kind") when we are in it

# drop (https://github.com/wrr/drop): its env's name
function prompt_om818-classic_env_drop() {
  if [[ -n "${DROP_ENV:-}" ]]; then
    REPLY="drop:${DROP_ENV}"
  elif [[ "${debian_chroot:-}" == 'drop' ]]; then
    REPLY='drop'
  fi
}

function prompt_om818-classic_env_container() {
  REPLY="$_om818_classic_container"
}

# A Debian chroot (schroot sets debian_chroot), drop aside
function prompt_om818-classic_env_chroot() {
  if [[ -n "${debian_chroot:-}" && "$debian_chroot" != 'drop' ]]; then
    REPLY="chroot:${debian_chroot}"
  fi
}

# Logged in through SSH (the host shows in the user segment: om818_prompt_host)
function prompt_om818-classic_env_ssh() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then REPLY='ssh'; fi
}

function prompt_om818-classic_env_flatpak() {
  if [[ -n "${FLATPAK_ID:-}" ]]; then REPLY="flatpak:${FLATPAK_ID##*.}"; fi
}

# nix-shell / nix develop: the derivation's name (nix sets $name), else pure or impure
function prompt_om818-classic_env_nix() {
  if [[ -n "${IN_NIX_SHELL:-}" ]]; then REPLY="nix:${name:-${IN_NIX_SHELL}}"; fi
}

function prompt_om818-classic_env_flox() {
  if [[ -n "${FLOX_ENV:-}" ]]; then REPLY="flox:${FLOX_ENV_DESCRIPTION:-${FLOX_ENV##*/}}"; fi
}

# A Python virtualenv: its folder's name, or its project's for the usual .venv, venv…
function prompt_om818-classic_env_venv() {
  if [[ -z "${VIRTUAL_ENV:-}" ]]; then return 0; fi
  local dir="${VIRTUAL_ENV%/}"
  case "${dir##*/}" in
  .venv | venv | .env | env) dir="${dir%/*}" ;;
  esac
  REPLY="venv:${dir##*/}"
}

# conda / mamba: the active environment (base included, as conda shows it)
function prompt_om818-classic_env_conda() {
  if [[ -n "${CONDA_DEFAULT_ENV:-}" && "${CONDA_SHLVL:-0}" -gt 0 ]]; then
    REPLY="conda:${CONDA_DEFAULT_ENV##*/}"
  fi
}

# The status of each command of the last pipeline (✘1, ✘1|0). Failed if any failed, with signal
# names (130 -> INT); suspended (Ctrl-Z) is not failed
function prompt_om818-classic_segment_status() {
  local s failed=0 shown=''
  for s in "${pst[@]}"; do
    if [[ "$s" -gt 128 ]]; then
      _om818_prompt_signal "$((s - 128))"
      if [[ -n "$REPLY" ]]; then s="$REPLY"; fi
    fi
    case "$s" in
    0 | TSTP | TTIN | TTOU) ;;
    *) failed=1 ;;
    esac
    shown+="${shown:+|}${s}"
  done
  if [[ "$failed" -eq 0 || ("$ran" -eq 0 && "$om818_prompt_status_sticky" != 'on') ]]; then
    REPLY="${_om818_classic_c[ok]}${_om818_classic_s[ok]}${_om818_classic_reset}"
  else
    REPLY="${_om818_classic_c[err]}${_om818_classic_s[err]}${shown}${_om818_classic_reset}"
  fi
}

# Duration of the last command, if long enough (none after an empty command line)
function prompt_om818-classic_segment_duration() {
  if [[ "$ran" -eq 0 || "$secs" -lt "$om818_prompt_duration_min" ]]; then return 0; fi
  prompt_om818-classic_duration "$secs"
  REPLY="${_om818_classic_c[duration]}${REPLY}${_om818_classic_reset}"
}

# The user (root in its color; om818_prompt_default_user hidden), then @host when it shows
# (om818_prompt_host)
function prompt_om818-classic_segment_user() {
  local name user host=''
  _om818_prompt_username
  name="$REPLY"
  _om818_prompt_user
  user="$REPLY"
  if [[ "$EUID" -eq 0 ]]; then
    user="${_om818_classic_c[root]}${user}${_om818_classic_reset}"
  elif [[ -n "$om818_prompt_default_user" && "$name" == "$om818_prompt_default_user" ]]; then
    user=''
  else
    user="${_om818_classic_c[user]}${user}${_om818_classic_reset}"
  fi
  if [[ -n "$_om818_host" ]]; then
    _om818_prompt_text "$_om818_host"
    host="${_om818_classic_c[host]}${user:+${_om818_classic_s[host_separator]}}${REPLY}"
    host+="${_om818_classic_reset}"
  fi
  REPLY="${user}${host}"
}

function prompt_om818-classic_segment_path() {
  _om818_prompt_path "$om818_prompt_path_depth" "${_om818_classic_s[path_ellipsis]}"
  REPLY="${_om818_classic_c[path]}${REPLY}${_om818_classic_reset}"
}

function prompt_om818-classic_segment_date() {
  _om818_prompt_date "$om818_prompt_date_format" "$om818_prompt_date_tz"
  _om818_prompt_text "$REPLY"
  REPLY="${_om818_classic_c[date]}${REPLY}${_om818_classic_reset}"
}

function prompt_om818-classic_segment_jobs() {
  _om818_prompt_jobs
  if [[ "$REPLY" -eq 0 ]]; then
    REPLY=''
    return 0
  fi
  REPLY="${_om818_classic_c[jobs]}${_om818_classic_s[jobs]}${REPLY}${_om818_classic_reset}"
}

# The indicators that have something to show, each in its color (see the header)
function prompt_om818-classic_segment_indicators() {
  local indicator shown='' color text
  for indicator in "${om818_prompt_indicators[@]}"; do
    if ! _om818_prompt_has_function "om818_indicator_${indicator}"; then continue; fi
    REPLY=''
    "om818_indicator_${indicator}"
    if [[ -z "$REPLY" ]]; then continue; fi
    _om818_prompt_text "$REPLY"
    text="$REPLY"
    color="${_om818_classic_c[indicator]}"
    if [[ -n "${om818_prompt_indicator_colors[$indicator]:-}" ]]; then
      _om818_prompt_color "${om818_prompt_indicator_colors[$indicator]}"
      color="$REPLY"
    fi
    shown+="${shown:+ }${color}${text}${_om818_classic_reset}"
  done
  REPLY=''
  if [[ -n "$shown" ]]; then
    REPLY="${_om818_classic_c[indicator_bracket]}${_om818_classic_s[indicator_prefix]}"
    REPLY+="${_om818_classic_reset}${shown}${_om818_classic_c[indicator_bracket]}"
    REPLY+="${_om818_classic_s[indicator_suffix]}${_om818_classic_reset}"
  fi
}

function prompt_om818-classic_segment_symbol() {
  if [[ "$EUID" -eq 0 ]]; then
    REPLY="${_om818_classic_s[root]}"
  else
    REPLY="${_om818_classic_s[user]}"
  fi
}

### Git

# Start gitstatusd with the configured limits, then query it
function prompt_om818-classic_git_start() {
  # gitstatusd reports at most this many: one more than max_count tells "more than max_count"
  local n="$((om818_prompt_git_max_count + 1))" d
  d="$n"
  if [[ "$om818_prompt_git_count_untracked" == 'off' ]]; then d=0; fi
  _om818_prompt_git_start -s "$n" -u "$n" -c "$n" -d "$d" -m "$om818_prompt_git_max_index_size"
  prompt_om818-classic_git_query
  prompt_om818-classic_render
}

# Query git status for $PWD (when the git segment shows), waiting at most
# om818_prompt_git_timeout: zsh redraws the prompt when the answer comes later
function prompt_om818-classic_git_query() {
  local pattern
  if [[ "$_om818_classic_shows_git" -eq 0 ]]; then return 0; fi
  # The segment of another directory would be wrong while waiting
  if [[ "$_om818_classic_git_pwd" != "$PWD" ]]; then _om818_classic_parts[git]=''; fi
  for pattern in "${_om818_classic_git_ignore[@]}"; do
    if _om818_prompt_match "$PWD" "$pattern"; then
      _om818_classic_parts[git]=''
      return 0
    fi
  done
  if ! _om818_prompt_git_query "$_om818_classic_git_timeout" prompt_om818-classic_git_done; then
    _om818_classic_parts[git]=''
  fi
}

# The answer: the segment, then the prompt again (it shows already when the answer came late)
function prompt_om818-classic_git_done() {
  prompt_om818-classic_git_format
  prompt_om818-classic_render
  _om818_prompt_redraw
}

# Set the git segment from the VCS_STATUS_* of the last query
function prompt_om818-classic_git_format() {
  local p='' r="$_om818_classic_reset" bracket="${_om818_classic_c[git_bracket]}" REPLY
  _om818_classic_parts[git]=''
  _om818_classic_git_pwd="$PWD"
  if [[ "$VCS_STATUS_RESULT" != ok-* ]]; then return 0; fi

  # Branch, else tag, else short commit (detached HEAD)
  local ref="${VCS_STATUS_LOCAL_BRANCH:-${VCS_STATUS_TAG:-@${VCS_STATUS_COMMIT:0:7}}}"
  _om818_prompt_text "$ref"
  p+="${bracket}${_om818_classic_s[git_prefix]}$r"
  p+="${_om818_classic_c[git_branch]}${REPLY}$r"
  if [[ -n "$VCS_STATUS_ACTION" ]]; then
    _om818_prompt_text "$VCS_STATUS_ACTION"
    p+="${_om818_classic_c[git_action]}:${REPLY}$r"
  fi
  prompt_om818-classic_git_part remote behind "$VCS_STATUS_COMMITS_BEHIND"
  prompt_om818-classic_git_part remote ahead "$VCS_STATUS_COMMITS_AHEAD"
  if [[ -n "$VCS_STATUS_LOCAL_BRANCH" && -z "$VCS_STATUS_REMOTE_BRANCH" ]]; then
    p+="${_om818_classic_c[git_no_upstream]}${_om818_classic_s[git_no_upstream]}$r"
  fi
  # Push remote, when it is not the upstream's (e.g. fork workflows: pull upstream, push origin)
  if [[ -n "$VCS_STATUS_PUSH_REMOTE_NAME" &&
    "$VCS_STATUS_PUSH_REMOTE_NAME" != "$VCS_STATUS_REMOTE_NAME" ]]; then
    prompt_om818-classic_git_part remote push_behind "$VCS_STATUS_PUSH_COMMITS_BEHIND"
    prompt_om818-classic_git_part remote push_ahead "$VCS_STATUS_PUSH_COMMITS_AHEAD"
  fi
  prompt_om818-classic_git_part stashes stashes "$VCS_STATUS_STASHES"
  p+="${bracket}${_om818_classic_s[git_separator]}$r"

  prompt_om818-classic_git_part staged staged "$VCS_STATUS_NUM_STAGED"
  # Unknown (-1) when the index is bigger than om818_prompt_git_max_index_size
  if [[ "$VCS_STATUS_HAS_UNSTAGED" -eq -1 ]]; then
    p+="${_om818_classic_c[git_unknown]}${_om818_classic_s[git_unknown]}$r"
  else
    prompt_om818-classic_git_part conflicts conflicts "$VCS_STATUS_NUM_CONFLICTED"
    prompt_om818-classic_git_part changed changed "$VCS_STATUS_NUM_UNSTAGED"
    prompt_om818-classic_git_part untracked untracked "$VCS_STATUS_NUM_UNTRACKED"
    if [[ "$VCS_STATUS_NUM_STAGED" -eq 0 && "$VCS_STATUS_NUM_CONFLICTED" -eq 0 &&
      "$VCS_STATUS_NUM_UNSTAGED" -eq 0 && "$VCS_STATUS_NUM_UNTRACKED" -eq 0 ]]; then
      p+="${_om818_classic_c[git_clean]}${_om818_classic_s[git_clean]}$r"
    fi
  fi
  p+="${bracket}${_om818_classic_s[git_suffix]}$r"
  _om818_classic_parts[git]="$p"
}

# Append to git_format's p a count with its color and symbol, unless it is 0 (counts above
# max_count show as "<max_count>+")
# usage: prompt_om818-classic_git_part <color> <symbol> <count>
function prompt_om818-classic_git_part() {
  local count="$3"
  if [[ "$count" -eq 0 ]]; then return 0; fi
  if [[ "$count" -gt "$om818_prompt_git_max_count" ]]; then
    count="${om818_prompt_git_max_count}+"
  fi
  p+="${_om818_classic_c[git_${1}]}${_om818_classic_s[git_${2}]}${count}${_om818_classic_reset}"
}

### Helpers

# Set REPLY to the time in microseconds ("-" without EPOCHREALTIME: bash < 5). zsh's has 9
# decimals, bash's 6, and the separator follows the locale
function prompt_om818-classic_now() {
  local t="${EPOCHREALTIME:-}" frac
  if [[ -z "$t" ]]; then
    REPLY='-'
    return 0
  fi
  frac="${t#*[.,]}000000"
  REPLY="${t%[.,]*}${frac:0:6}"
}

# Set REPLY to a duration in seconds, human-readable: 42s, 3m07s, 2h05m
function prompt_om818-classic_duration() {
  local t="$1" hi lo
  if [[ "$t" -ge 3600 ]]; then
    hi="$((t / 3600))" lo="0$((t % 3600 / 60))"
    REPLY="${hi}h${lo: -2}m"
  elif [[ "$t" -ge 60 ]]; then
    hi="$((t / 60))" lo="0$((t % 60))"
    REPLY="${hi}m${lo: -2}s"
  else
    REPLY="${t}s"
  fi
}
