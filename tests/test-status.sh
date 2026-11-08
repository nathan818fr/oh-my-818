#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088 # shell code in single quotes, and the report shows ~
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of `om818 status`: a report to share, showing what can break oh-my-818.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

OM818='.local/share/om818/bin/om818'

function test_clean_install_reports_nothing_to_fix() {
  local daemon
  install
  # gitstatusd, as the install downloads it (the tests don't download)
  daemon="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
  mkdir -p -- "${SANDBOX}/home/.cache/om818/gitstatus"
  : >"${SANDBOX}/home/.cache/om818/gitstatus/gitstatusd-${daemon}"
  run "${SANDBOX}/home/${OM818}" status
  assert_status 0
  assert_output_contains 'oh-my-818 v0.1.0 (~/.local/share/om818)'
  assert_output_contains '~/.local/state/om818/env.sh: ok'
  for file in .zshenv .config/zsh/.zshrc .profile .bashrc; do
    assert_output_contains "~/${file}: ok"
  done
  # No false alarm, and the home directory shown as ~ (a report to share)
  assert_output_not_contains 'missing'
  assert_output_not_contains 'old locations'
  assert_output_not_contains 'error'
  assert_output_not_contains "${SANDBOX}/home"
  if [[ "$OUTPUT" == *$'\n!'* ]]; then fail 'a row marked as a problem'; fi
  if [[ "$OUTPUT" != *$'\n\nAll good.' ]]; then fail 'no verdict'; fi
}

function test_reports_problems() {
  home_file .zshrc '# old'
  home_file .zsh_history 'ls'
  home_file .bash_history 'ls'
  home_file .bash_profile '# mine'
  mkdir -p -- "${SANDBOX}/home/.cargo"
  install
  # A line removed after the install
  printf '# mine\n' >"${SANDBOX}/home/.bash_profile"
  home_file .config/om818/config.sh 'om818_promt_date_tz=UTC
om818_fzf=on
om818_xdg_go=off'
  # (older than config.sh for sure: busybox's sh compares whole seconds)
  touch -t 200001010000 -- "${SANDBOX}/home/.local/state/om818/env.sh"
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains '! ~/.bash_profile: no om818 line: bash login shells read it instead'
  assert_output_contains '! ~/.zshrc: not read (zsh reads ~/.config/zsh/.zshrc)'
  assert_output_contains \
    '! settings     ~/.config/om818/config.sh: unknown settings: om818_promt_date_tz'
  assert_output_contains "~/.zsh_history: old zsh history, no longer read (oh-my-818's:"
  assert_output_contains \
    '~/.cargo: in use, so not moved: mv ~/.cargo ~/.local/share/cargo && om818 env'
  assert_output_contains 'older than config.sh'
  # Counted at the end: the rows that need action, not the optional tidying
  assert_output_contains $'\n\n5 things to fix (marked !): each line says how.'
}

function test_read_only_startup_files() {
  # rc files protected from installers that append to them, and a ~/.zshrc guard
  install
  : >"${SANDBOX}/home/.zshrc"
  chmod a-w "${SANDBOX}/home/.zshrc" "${SANDBOX}/home/.zshenv" \
    "${SANDBOX}/home/.config/zsh/.zshrc"
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains '~/.zshenv: ok (loads the environment in zsh, read-only)'
  assert_output_contains '~/.config/zsh/.zshrc: ok (loads oh-my-818 in zsh, read-only)'
  assert_output_contains '~/.zshrc: empty read-only guard: ok'
  assert_output_not_contains 'ignored'
  # Installing again changes nothing, and doesn't call the guard ignored
  install
  assert_output_not_contains 'ignored'
  assert_output_not_contains 'added'
}

function test_reports_config_mistakes() {
  # A typo that stops sh reading ~/.profile
  home_file .config/om818/env.d/10-env.sh 'if [ -n x ]; then export EDITOR=nano'
  install
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains '1 env.d file(s) with a syntax error: sh -n ~/.config/om818/env.d/*.sh'

  # A wrong value, a typo inside a condition
  home_file .config/om818/config.sh 'om818_history=no
if true; then om818_updat=off; fi'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'unknown settings: om818_updat'
  assert_output_contains 'invalid values: om818_history=no (on or off)'
  # A config the shell can't read: its error, with the line
  home_file .config/om818/config.sh 'om818_prompt_colours[path]=33'
  run "${SANDBOX}/home/${OM818}" status
  # (a typo in a table's name, an error in zsh: the name shown too)
  assert_output_contains "config.sh: an error at line 1 (unknown settings: om818_prompt_colours):"
  assert_output_contains \
    "zsh -c '. ~/.local/share/om818/defaults.sh; . ~/.config/om818/config.sh' shows it"
  # The rest of the report with the defaults, not as a broken install
  assert_output_contains 'integrations (config.sh has an error: the defaults)'
  assert_output_contains 'config.sh has an error: fix it, then open a new terminal'
  assert_output_not_contains 'no setting'
  run "${SANDBOX}/home/${OM818}" env
  assert_status 1
  assert_output_contains 'error: ~/.config/om818/config.sh has an error (see above)'
}

function test_reports_an_old_fzf() {
  fake_tool fzf 'printf "%s\n" "0.44.1 (debian)"'
  home_file .config/om818/config.sh 'om818_fzf=on'
  install
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'fzf               off  fzf 0.48+ needed (found 0.44.1)'
}

function test_reports_an_outdated_environment() {
  install
  # A tool with a part in the environment (its shims), installed after it was generated
  fake_tool mise
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'out of date (tools changed since): om818 env'
}

# config.sh removed: the environment (its settings) is regenerated, as when it changes
function test_environment_after_config_removed() {
  home_file .config/om818/config.sh 'om818_fzf=on'
  install
  # (no other reason to regenerate it: a version older than it)
  touch -t 200001010000 -- "${SANDBOX}/home/.local/state/om818/env.sh"
  touch -t 199901010000 -- "${SANDBOX}/home/.local/share/om818/.git/HEAD"
  rm -- "${SANDBOX}/home/.config/om818/config.sh"
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'env.sh: config.sh removed since, regenerated by the next new terminal'
  zsh_i ':'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'env.sh: ok'
}

function test_config_error_shows_no_value() {
  install
  # A broken line holding a secret: the report is shared, so only the line number
  home_file .config/om818/config.sh 'om818_fzf=on
TOKEN= ghp_secret123'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'config.sh: an error at line 2'
  assert_output_not_contains 'ghp_secret123'
}

function test_reports_an_unknown_sandbox() {
  install
  # A list item with a typo would be dropped silently
  home_file .config/om818/config.sh 'om818_sandboxes=(drop dockerr)'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'invalid values: om818_sandboxes:dockerr'
}

function test_reports_the_sandbox_only_commands() {
  home_file .config/om818/config.sh 'om818_sandbox_only=(claude)'
  install
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'claude (only inside: drop, container)'
}

# ~ only for the home folder as a whole path: not for a folder next to it whose name starts the
# same, nor where the home's path is the end of another one (here both in om818's folder)
function test_home_shown_as_tilde_only_as_a_whole_path() {
  local data="${SANDBOX}/home2${SANDBOX}/home"
  install XDG_DATA_HOME="$data"
  run XDG_DATA_HOME="$data" "${data}/om818/bin/om818" status
  assert_output_contains "oh-my-818 v0.1.0 (${data}/om818)"
  # (the home's path right after itself: one ~, at the start)
  data="${SANDBOX}/home${SANDBOX}/home"
  install XDG_DATA_HOME="$data"
  run XDG_DATA_HOME="$data" "${data}/om818/bin/om818" status
  assert_output_contains "oh-my-818 v0.1.0 (~${SANDBOX}/home/om818)"
}

# HOME empty (a broken environment): status still ends, with the full paths
function test_status_with_an_empty_home() {
  local h="${SANDBOX}/home"
  install
  RUN_TIMEOUT=10 run HOME= XDG_CONFIG_HOME="${h}/.config" XDG_STATE_HOME="${h}/.local/state" \
    XDG_DATA_HOME="${h}/.local/share" XDG_CACHE_HOME="${h}/.cache" \
    "${h}/.local/share/om818/bin/om818" status
  assert_output_contains "oh-my-818 v0.1.0 (${h}/.local/share/om818)"
  assert_output_not_contains 'run: killed'
}

# A login shell oh-my-818 doesn't run in (useradd's /bin/sh): a thing to fix (without the login
# name: the report may be shared)
function test_reports_the_login_shell() {
  install
  run SHELL=/bin/sh "${SANDBOX}/home/${OM818}" status
  assert_output_matches \
    '! login +/bin/sh runs no oh-my-818: chsh -s /[^ ]+ \(else: sudo usermod -s … \$USER\)'
}

# A tool's old folder the user's own variable points to (GOPATH="$HOME/go" moved to env.d/ from
# an old ~/.zshrc): not advised to move
function test_no_move_advised_for_a_folder_the_user_set() {
  mkdir -p -- "${SANDBOX}/home/go"
  install
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains '~/go: in use, so not moved'
  # (from a terminal, which loaded it)
  home_file .config/om818/env.d/10-go.sh 'export GOPATH="$HOME/go"'
  run GOPATH="${SANDBOX}/home/go" "${SANDBOX}/home/${OM818}" status
  assert_output_not_contains '~/go: in use'
}

# The update file's check time, read as a number only: nothing in it runs, in status nor in a
# starting shell (bash runs a $(…) in the subscript of a variable's name)
function test_gitstatusd_not_used() {
  local config reason
  fake_tool starship
  install
  # A gitstatusd downloaded before: left, listed as unused. Git status off, no theme, or starship
  # drawing the prompt: nothing uses it, nothing to fix
  mkdir -p -- "${SANDBOX}/home/.cache/om818/gitstatus"
  for config in 'om818_prompt_git=off' 'om818_theme=off' 'om818_starship=on'; do
    reason="$config"
    if [[ "$config" == 'om818_starship=on' ]]; then reason='starship draws the prompt'; fi
    home_file .config/om818/config.sh "$config"
    run "${SANDBOX}/home/${OM818}" status
    assert_output_contains "  gitstatusd   not used (${reason})"
    assert_output_contains \
      "~/.cache/om818/gitstatus: unused (${reason}): rm -r ~/.cache/om818/gitstatus"
    if [[ "$OUTPUT" != *$'\n\nAll good.' ]]; then fail "not all good with ${config}"; fi
  done
}

function test_integrations_auto_off() {
  local daemon
  fake_tool mise
  fake_tool direnv
  install
  # gitstatusd, as the install downloads it (the tests don't download)
  daemon="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"
  mkdir -p -- "${SANDBOX}/home/.cache/om818/gitstatus"
  : >"${SANDBOX}/home/.cache/om818/gitstatus/gitstatusd-${daemon}"
  home_file .config/om818/config.sh 'om818_integrations_auto=off
om818_mise=on'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains '  mise              on   om818_mise=on, found'
  assert_output_contains \
    '  direnv            off  om818_integrations_auto=off (om818_direnv=auto)'
  # Off on purpose: nothing to fix
  if [[ "$OUTPUT" != *$'\n\nAll good.' ]]; then fail 'not all good'; fi
}

function test_completion_off_turns_tool_completions_off() {
  # Generated completions that nothing would load: off, with the reason (no "!": nothing to fix)
  home_file .config/om818/config.sh 'om818_completion=off'
  install
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains $'\n  tool_completions  off  om818_completion=off\n'
}

function test_update_file_runs_nothing() {
  install
  # shellcheck disable=SC2016 # written as is
  printf 'checked=HOME[$(touch "$HOME/ran")]\n' >"${SANDBOX}/home/.local/state/om818/update"
  run "${SANDBOX}/home/${OM818}" status
  if [[ -e "${SANDBOX}/home/ran" ]]; then fail 'the update file ran a command'; fi
  assert_output_contains 'not checked yet'
  bash_i ':'
  if [[ -e "${SANDBOX}/home/ran" ]]; then fail 'a starting bash ran the update file'; fi
}

run_tests "$@"
