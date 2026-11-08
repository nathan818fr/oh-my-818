#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088 # shell code in single quotes, and prompts show ~
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of the om818-classic theme. Its code is shared by zsh and bash, each with its own prompt
# layer (modules/<shell>/prompt.*): each test runs in both shells.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# Code printing the prompt as plain text (after running the theme's precmd)
PROMPT_CODE='source "$TESTS_DIR/plain.$om818_shell"; print_prompt'

# Answers of gitstatus (VCS_STATUS_*), without gitstatusd: a branch ahead by 2, with a stash, 1
# staged, 3 changed and 120 untracked files
GIT_ANSWER='VCS_STATUS_RESULT=ok-sync VCS_STATUS_LOCAL_BRANCH=main VCS_STATUS_TAG=
  VCS_STATUS_COMMIT=0 VCS_STATUS_ACTION= VCS_STATUS_COMMITS_BEHIND=0 VCS_STATUS_COMMITS_AHEAD=2
  VCS_STATUS_REMOTE_BRANCH=main VCS_STATUS_REMOTE_NAME=origin VCS_STATUS_PUSH_REMOTE_NAME=
  VCS_STATUS_STASHES=1 VCS_STATUS_NUM_STAGED=1 VCS_STATUS_HAS_UNSTAGED=1
  VCS_STATUS_NUM_CONFLICTED=0 VCS_STATUS_NUM_UNSTAGED=3 VCS_STATUS_NUM_UNTRACKED=120'

# Set the prompt's lines (and other settings) in config.sh
# usage: prompt_config <line1> <line2> [<more settings>]
function prompt_config() {
  home_file .config/om818/config.sh "om818_prompt_line1=($1)
om818_prompt_line2=($2)
${3:-}"
}

function test_default_prompt() {
  local shell
  install
  for shell in zsh bash; do
    shell_i "$shell" "cd ~; ${PROMPT_CODE}"
    assert_status 0
    assert_output_matches "^✔ $(id -un) ~"$'\n''[0-9][0-9]:[0-9][0-9] \$ $'
    # The last command's result first, then where you are (an environment, the user…)
    shell_i "$shell" VIRTUAL_ENV=/srv/api/.venv "cd ~; ${PROMPT_CODE}"
    assert_output_matches "^✔ \(venv:api\) $(id -un) ~"$'\n'
  done
}

function test_lines_and_settings() {
  local shell
  # "+name": no space before it; date format and time zone; a symbol of a table changed; a line
  # left empty (no second line)
  prompt_config 'status +path' 'date symbol' "om818_prompt_date_tz=UTC
om818_prompt_date_format='%Z'
om818_prompt_symbols[user]='>'"
  install
  for shell in zsh bash; do
    shell_i "$shell" "cd ~; ${PROMPT_CODE}"
    assert_output_eq '✔~
UTC > '
  done
  prompt_config 'path symbol' ''
  for shell in zsh bash; do
    shell_i "$shell" "cd ~; ${PROMPT_CODE}"
    assert_output_eq '~ $ '
  done
}

function test_colors() {
  # Each shell's layer turns color settings into its own escapes: a #rrggbb color after bold;
  # basic mode's 8 colors, which the Linux console knows
  home_file .config/om818/config.sh "om818_prompt_colors[path]='bold #ff8700'"
  install
  zsh_i 'cd ~; prompt_om818-classic_precmd; print -r -- "$PROMPT"'
  assert_output_contains '%B%F{#ff8700}%~'
  bash_i 'cd ~; prompt_om818-classic_precmd; printf "%q\n" "$_om818_ps1"'
  assert_output_contains '\001\E[1m\002\001\E[38;2;255;135;0m\002~'
  home_file .config/om818/config.sh 'om818_prompt_basic=on'
  zsh_i 'cd ~; prompt_om818-classic_precmd; print -r -- "$PROMPT"'
  assert_output_contains '%F{yellow}%~'
  bash_i 'cd ~; prompt_om818-classic_precmd; printf "%q\n" "$_om818_ps1"'
  assert_output_contains '\001\E[33m\002~'
}

function test_basic_mode_is_automatic() {
  local shell
  # The C locale (also what a locale the system lacks, e.g. sent by an SSH client, falls back to,
  # except with musl, which takes any name as UTF-8), where a Unicode symbol breaks the line
  # editor's cursor; the Linux console has no such symbols
  prompt_config status ''
  install
  for shell in zsh bash; do
    shell_i "$shell" LANG=C "$PROMPT_CODE"
    assert_output_contains '+'
    assert_output_not_contains '✔'
    # (its terminfo adds an invisible character to the color reset)
    shell_i "$shell" TERM=linux "$PROMPT_CODE"
    assert_output_contains '+'
    assert_output_not_contains '✔'
  done
}

function test_path_depth() {
  local shell
  mkdir -p -- "${SANDBOX}/home/a/b/c d" "${SANDBOX}/home/x"
  prompt_config path '' 'om818_prompt_path_depth=2'
  install
  for shell in zsh bash; do
    shell_i "$shell" 'source "$TESTS_DIR/plain.$om818_shell"
      cd ~/a/b/c\ d; print_prompt; cd ~/x; print_prompt; cd /; print_prompt'
    assert_output_eq $'…/b/c d \n~/x \n/ '
  done
}

function test_environments() {
  local shell
  prompt_config env ''
  install
  # drop, an SSH session and a project's .venv at once, in om818_prompt_envs' order
  for shell in zsh bash; do
    shell_i "$shell" DROP_ENV=dev SSH_CONNECTION='1 2 3 4' VIRTUAL_ENV=/p/api/.venv "$PROMPT_CODE"
    assert_output_eq '(drop:dev ssh venv:api) '
  done
  prompt_config env '' 'om818_prompt_envs=(venv drop)'
  for shell in zsh bash; do
    shell_i "$shell" DROP_ENV=dev VIRTUAL_ENV=/p/tools "$PROMPT_CODE"
    assert_output_eq '(venv:tools drop:dev) '
  done
}

function test_status_and_duration() {
  local shell
  prompt_config 'status duration' ''
  install
  # A failed pipeline: each command's status. zsh has $pipestatus; bash-preexec keeps a copy of
  # bash's PIPESTATUS (BP_PIPESTATUS), which a background command (`sleep 9 &`) doesn't update,
  # unlike $? (__bp_last_ret_value)
  zsh_i 'source "$TESTS_DIR/plain.zsh"; prompt_om818-classic_preexec; false | true; print_prompt'
  assert_output_eq '✘1|0 '
  bash_i 'source "$TESTS_DIR/plain.bash"
    prompt_om818-classic_preexec; BP_PIPESTATUS=(1 0) __bp_last_ret_value=0; print_prompt
    prompt_om818-classic_preexec; BP_PIPESTATUS=(1) __bp_last_ret_value=0; print_prompt'
  assert_output_eq $'✘1|0 \n✔ '
  # A command that started 65 seconds ago, then a quick one (its duration hidden): the shells'
  # clocks differ in precision (zsh: ns, bash: µs). (bash 4.4 has no clock: no duration)
  for shell in zsh bash; do
    if [[ "$shell" == bash ]] && ((BASH_VERSINFO[0] < 5)); then continue; fi
    shell_i "$shell" 'source "$TESTS_DIR/plain.$om818_shell"; prompt_om818-classic_preexec
      _om818_classic_cmd_start="$((_om818_classic_cmd_start - 65000000))"; print_prompt
      prompt_om818-classic_preexec; print_prompt'
    assert_output_eq $'✔ 1m05s \n✔ '
  done
}

function test_user_and_host() {
  local shell user host
  user="$(id -un)"
  host="$(uname -n)"
  host="${host%%.*}"
  prompt_config user ''
  install
  for shell in zsh bash; do
    shell_i "$shell" "$PROMPT_CODE"
    assert_output_eq "${user} "
    # Over SSH or under sudo: the host too
    shell_i "$shell" SSH_CONNECTION='1 2 3 4' "$PROMPT_CODE"
    assert_output_eq "${user}@${host} "
    shell_i "$shell" SUDO_USER=someone "$PROMPT_CODE"
    assert_output_eq "${user}@${host} "
  done
  prompt_config user '' "om818_prompt_host=on
om818_prompt_default_user=${user}"
  for shell in zsh bash; do
    shell_i "$shell" "$PROMPT_CODE"
    assert_output_eq "${host} "
  done
}

function test_git_segment() {
  local shell
  install
  for shell in zsh bash; do
    shell_i "$shell" "${GIT_ANSWER}"'
      prompt_om818-classic_git_format
      source "$TESTS_DIR/plain.$om818_shell"; plain "${_om818_classic_parts[git]}"'
    assert_output_eq '[main↑2≡1|●1✚3…99+]'
  done
}

function test_git_settings() {
  local shell
  mkdir -p -- "${SANDBOX}/home/big/repo"
  install
  # The timeout's default: zsh redraws the prompt when git answers late, bash can't
  zsh_i 'print -r -- "$_om818_classic_git_timeout"'
  assert_output_eq '0.02'
  bash_i 'printf "%s\n" "$_om818_classic_git_timeout"'
  assert_output_eq '0.5'
  # Set, and ~/ in a git_ignore pattern (zsh expands it in patterns, bash doesn't)
  home_file .config/om818/config.sh "om818_prompt_git_timeout=1.5
om818_prompt_git_ignore=('~/big/*')"
  for shell in zsh bash; do
    shell_i "$shell" 'cd ~/big/repo; printf "%s\n" "$_om818_classic_git_timeout"
      for p in "${_om818_classic_git_ignore[@]}"; do
        if _om818_prompt_match "$PWD" "$p"; then printf "%s\n" ignored; fi
      done'
    assert_output_eq '1.5
ignored'
  done
}

function test_without_gitstatusd() {
  local shell
  # Not downloaded (offline, no curl): no git segment, nothing printed. Nor downloaded by the
  # shell, which would wait on the network at each start: checked through gitstatus's setting
  # (here, without a terminal, gitstatus fails before it would download)
  install
  for shell in zsh bash; do
    shell_i "$shell" 'prompt_om818-classic_late_init
      printf "%s\n" "ready ${_om818_prompt_git_started} ${GITSTATUS_AUTO_INSTALL-unset}"'
    assert_output_eq 'ready 0 0'
  done
}

function test_git_status_off() {
  local shell
  # om818_prompt_git=off: no gitstatus loaded, nothing started, no git segment, nothing printed,
  # with git still in the prompt's lines
  home_file .config/om818/config.sh 'om818_prompt_git=off'
  install
  git_ init -q "${SANDBOX}/home/repo"
  for shell in zsh bash; do
    shell_i "$shell" 'cd ~/repo; prompt_om818-classic_late_init
      if typeset -f gitstatus_start >/dev/null; then printf "%s\n" loaded; fi
      printf "%s\n" "${_om818_classic_shows_git} ${GITSTATUS_CACHE_DIR-unset}"
      '"${PROMPT_CODE}"
    assert_output_matches "^0 unset"$'\n'"✔ $(id -un) ~/repo"$'\n'
  done
}

function test_indicators() {
  # Text from outside, shown as is (% and $ are prompt syntax), in the order of the setting;
  # one with nothing to show is left out; one that doesn't exist is reported once shell.d is read
  home_file .config/om818/shell.d/indicators.sh \
    "function om818_indicator_todo() { REPLY='todo%\$'; }
function om818_indicator_none() { REPLY=''; }
function om818_indicator_mail() { REPLY='mail'; }
om818_prompt_indicators=(todo none mail)"
  prompt_config indicators ''
  install
  for shell in zsh bash; do
    shell_i "$shell" "$PROMPT_CODE"
    assert_output_eq '{todo%$ mail} '
    shell_i "$shell" 'om818_prompt_indicators+=(nope); prompt_om818-classic_check_indicators'
    assert_output_eq 'oh-my-818: prompt indicator nope has no om818_indicator_nope function'
  done
}

function test_unknown_keys_warn() {
  local shell
  home_file .config/om818/config.sh "om818_prompt_colors[pth]=33
om818_prompt_symbols_basic[okk]='+'"
  install
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" ready'
    assert_output_eq 'oh-my-818: unknown key in om818_prompt_colors: pth (a typo? see defaults.sh)
oh-my-818: unknown key in om818_prompt_symbols_basic: okk (a typo? see defaults.sh)
ready'
  done
}

function test_hostile_names_stay_text() {
  local shell
  # Names from a cloned repo or an archive: a directory whose name drives the terminal (sets its
  # clipboard), a branch named to run a command. zsh: with prompt_subst on (oh-my-zsh sets it),
  # the prompt is expanded again before showing
  mkdir -p -- "${SANDBOX}/home/a"$'\e]52;c;eA==\a'"b"
  prompt_config 'env path git' ''
  install
  for shell in zsh bash; do
    shell_i "$shell" VIRTUAL_ENV=$'/p/a\e]52;c;eA==\ab' 'cd ~/a*b; '"$PROMPT_CODE"
    assert_output_contains '(venv:a?]52;c;eA==?b) '
  done
  # (zsh's own path escape shows the character as ^[)
  bash_i 'cd ~/a*b; '"$PROMPT_CODE"
  assert_output_eq '~/a?]52;c;eA==?b '
  for shell in zsh bash; do
    shell_i "$shell" 'cd ~/a*b; t="$(_om818_title_precmd)"
      expected=$'"'"'\e]2;~/a?]52;c;eA==?b\a'"'"'
      if [[ "$t" == "$expected" ]]; then printf "%s\n" replaced; fi'
    assert_output_eq 'replaced'
  done
  zsh_i "setopt prompt_subst; ${GIT_ANSWER}"'
    VCS_STATUS_LOCAL_BRANCH="\$(touch ~/ran)"
    cd ~; prompt_om818-classic_git_format; prompt_om818-classic_render; print -P -- "$PROMPT"'
  assert_output_contains '$(touch ~/ran)'
  if [[ -e "${SANDBOX}/home/ran" ]]; then fail 'the branch name ran'; fi
}

function test_jobs() {
  prompt_config '' 'jobs symbol'
  install
  # bash counts its jobs with a fork: a real interactive bash, reading its commands from stdin (it
  # prints its prompts on stderr), with a job, then without. (Not tested here: at a terminal, a
  # finished job bash hasn't reported yet isn't counted; without one, bash drops it at once)
  run bash -c 'printf "%s\n" "sleep 30 &" "kill %1" "sleep 0.2" ":" |
    bash --rcfile ~/.bashrc -i 2>&1 >/dev/null |
    tr -d "\001\002" | sed -e "$1"' _ $'s/\e\\[[0-9;]*m//g; s/\e\\]2;[^\a]*\a//g' # (macOS: no \x1b)
  assert_output_contains '⚙1 $'
  if [[ "${OUTPUT##*$'\n'}" != '$ '* ]]; then fail 'a job after it was killed'; fi
}

# ~ only for the home folder and what is in it: not for a folder next to it whose name starts the
# same (HOME=/home/al, /home/alice)
function test_path_next_to_home() {
  local shell
  mkdir -p -- "${SANDBOX}/home2"
  prompt_config path ''
  install
  for shell in zsh bash; do
    shell_i "$shell" 'source "$TESTS_DIR/plain.$om818_shell"; cd "${HOME}2"; print_prompt
      _om818_title_precmd'
    assert_output_eq "${SANDBOX}/home2 "$'\n\e]2;'"${SANDBOX}/home2"$'\a'
  done
}

run_tests "$@"
