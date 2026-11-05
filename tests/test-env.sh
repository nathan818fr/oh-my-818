#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088 # shell code in single quotes, and outputs show ~
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of the generated environment: valid in every shell, idempotent, integrations, user file.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

ENV_FILE='.local/state/om818/env.sh'

function test_sources_in_every_shell_and_twice() {
  local shell
  install
  for shell in sh bash 'zsh -f'; do
    run $shell -c '. "$HOME/'"$ENV_FILE"'"; a="$PATH"
      . "$HOME/'"$ENV_FILE"'"; [ "$a" = "$PATH" ] && echo same'
    assert_status 0
    assert_output_eq 'same'
  done
}

function test_puts_om818_and_local_bin_on_path() {
  mkdir -p -- "${SANDBOX}/home/.local/bin"
  install
  run sh -c '. "$HOME/'"$ENV_FILE"'"; echo "$PATH"'
  assert_output_contains "${SANDBOX}/home/.local/bin:"
  assert_output_contains ":${SANDBOX}/home/.local/share/om818/bin"
  run sh -c '. "$HOME/'"$ENV_FILE"'"; om818 version'
  assert_output_eq 'v0.1.0'
}

function test_sources_env_d_last_in_name_order() {
  home_file .config/om818/env.d/20-b.sh 'export MY_VAR="${MY_VAR:-} b"
om818_path_prepend /b'
  home_file .config/om818/env.d/10-a.sh 'export MY_VAR=a'
  home_file .config/om818/env.d/notes.txt 'export MY_VAR=ignored'
  install
  local shell
  for shell in sh bash 'zsh -f'; do
    run $shell -c '. "$HOME/'"$ENV_FILE"'"; echo "$MY_VAR $PATH"'
    assert_output_contains 'a b /b:'
  done
  # No files: nothing fails (zsh would, on a glob without matches)
  rm -f -- "${SANDBOX}/home/.config/om818/env.d/"*
  run zsh -fc '. "$HOME/'"$ENV_FILE"'" && echo fine'
  assert_output_eq 'fine'
}

function test_path_functions() {
  install
  run sh -c '. "$HOME/'"$ENV_FILE"'"; PATH=/a:/b:/c; om818_path_remove /b; om818_path_prepend /c;
    om818_path_prepend /d; om818_path_append /a; om818_path_append /e; echo "$PATH"'
  assert_output_eq '/d:/a:/c:/e'
  run sh -c '. "$HOME/'"$ENV_FILE"'"; PATH=/a:/b; om818_path_first /b; om818_path_first /z
    om818_path_first /b; echo "$PATH $OM818_PATH_FIRST"'
  assert_output_eq '/b:/z:/a /b:/z'
}

function test_xdg_redirects_only_without_the_old_folder() {
  mkdir -p -- "${SANDBOX}/home/.gradle"
  home_file .config/om818/config.sh 'om818_xdg_go=off'
  install
  run sh -c '. "$HOME/'"$ENV_FILE"'"
    echo "cargo=${CARGO_HOME:-} gradle=${GRADLE_USER_HOME:-} go=${GOPATH:-}"'
  assert_output_eq "cargo=${SANDBOX}/home/.local/share/cargo gradle= go="
  # Where cargo installs commands, in front of the system's folders (rustup's cargo before a
  # distribution's)
  run sh -c '. "$HOME/'"$ENV_FILE"'"; echo "$PATH"'
  if [[ "$OUTPUT" != *"/.local/share/cargo/bin:"*"${TEST_DIR}/sysbin"* ]]; then
    fail "cargo's bin not in front of PATH"
  fi
}

function test_podman_for_docker_clients() {
  fake_tool podman
  home_file .config/om818/config.sh 'om818_podman=on'
  mkdir -p -- "${SANDBOX}/run"
  install XDG_RUNTIME_DIR="${SANDBOX}/run"
  # Not where it never applies: macOS, a machine running Docker (e.g. GitHub's runners)
  if [[ "$(uname -s)" != 'Linux' || -S /var/run/docker.sock ]]; then
    if grep -q DOCKER_HOST "${SANDBOX}/home/${ENV_FILE}"; then fail 'DOCKER_HOST set'; fi
    return 0
  fi
  assert_file_contains "$ENV_FILE" "export DOCKER_HOST='unix://${SANDBOX}/run/podman/podman.sock'"
  # A rootless Docker running: left to it
  # (zsh's socket module: perl isn't on every CI host)
  zsh -fc 'zmodload zsh/net/socket && zsocket -l "$1"' zsh "${SANDBOX}/run/docker.sock"
  run XDG_RUNTIME_DIR="${SANDBOX}/run" "${SANDBOX}/home/.local/share/om818/bin/om818" env
  if grep -q DOCKER_HOST "${SANDBOX}/home/${ENV_FILE}"; then fail 'DOCKER_HOST set'; fi
}

function test_mise_shims() {
  fake_tool mise
  install
  assert_file_contains "$ENV_FILE" "om818_path_prepend '${SANDBOX}/home/.local/share/mise/shims'"
}

function test_a_failing_integration_stops_the_generation() {
  # (busybox's sh drops errexit inside $(…); and Homebrew doesn't run on musl)
  if system_brew || sh_is_busybox; then return 0; fi
  install
  # Homebrew whose `brew --prefix` fails: no environment with an empty prefix, the old one stays
  home_file .linuxbrew/bin/brew '#!/bin/sh
exit 1'
  chmod +x "${SANDBOX}/home/.linuxbrew/bin/brew"
  run "${SANDBOX}/home/.local/share/om818/bin/om818" env
  assert_status 1
  if grep -q HOMEBREW "${SANDBOX}/home/${ENV_FILE}"; then fail 'a broken environment'; fi
  if compgen -G "${SANDBOX}/home/${ENV_FILE}.tmp.*" >/dev/null; then fail 'a file left'; fi
}

function test_homebrew_prefix_must_be_absolute() {
  local prefix
  if system_brew; then return 0; fi
  install
  # A prefix relative to om818's working folder, or without its bin folder: not put on PATH
  for prefix in home/.linuxbrew "${SANDBOX}/home/missing"; do
    home_file .linuxbrew/bin/brew '#!/bin/sh
echo '"$prefix"
    chmod +x "${SANDBOX}/home/.linuxbrew/bin/brew"
    run "${SANDBOX}/home/.local/share/om818/bin/om818" env --quiet
    run sh -c '. "$HOME/'"$ENV_FILE"'"; echo "prefix=${HOMEBREW_PREFIX:-} $PATH"'
    assert_output_contains 'prefix= '
    assert_output_not_contains "$prefix"
  done
}

function test_xdg_keeps_a_redirection_in_use() {
  # The new folder in use, then the old one comes back (e.g. a tool run without the variable)
  mkdir -p -- "${SANDBOX}/home/.local/share/cargo" "${SANDBOX}/home/.cargo"
  install
  assert_file_contains "$ENV_FILE" "export CARGO_HOME='${SANDBOX}/home/.local/share/cargo'"
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains '~/.cargo: both it and ~/.local/share/cargo exist'
}

function test_home_with_a_space_and_a_quote() {
  local home="${SANDBOX}/it's my home"
  mkdir -p -- "$home"
  install HOME="$home"
  run HOME="$home" sh -c '. "$HOME/'"$ENV_FILE"'"; echo "$CARGO_HOME"'
  assert_output_eq "${home}/.local/share/cargo"
}

function test_homebrew() {
  if system_brew; then return 0; fi
  # Homebrew on Linux, where it isn't on PATH before the environment
  home_file .linuxbrew/bin/brew '#!/bin/sh
case "$1" in
--prefix) echo "$HOME/.linuxbrew" ;;
--repository) echo "$HOME/.linuxbrew/repo" ;;
esac'
  chmod +x "${SANDBOX}/home/.linuxbrew/bin/brew"
  mkdir -p -- "${SANDBOX}/home/.linuxbrew/share/zsh/site-functions"
  install
  run sh -c '. "$HOME/'"$ENV_FILE"'"; echo "$HOMEBREW_PREFIX $PATH"'
  assert_output_contains "${SANDBOX}/home/.linuxbrew "
  assert_output_contains ":${SANDBOX}/home/.linuxbrew/bin:"
  # zsh only looks for completions in Intel Macs' Homebrew
  zsh_i 'print -r -- ${fpath[(r)*/.linuxbrew/share/zsh/site-functions]}'
  assert_output_eq "${SANDBOX}/home/.linuxbrew/share/zsh/site-functions"
}

function test_env_d_once_per_login() {
  # Debian's ~/.profile sources ~/.bashrc, which loads the environment too: env.d/ runs once
  home_file .config/om818/env.d/10-count.sh 'printf x >>"$HOME/runs"'
  home_file .profile 'if [ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi'
  install
  rm -f -- "${SANDBOX}/home/runs"
  run bash --norc --noprofile -c '. ~/.profile'
  if [[ "$(<"${SANDBOX}/home/runs")" != 'x' ]]; then fail 'env.d/ read more than once'; fi
}

function test_unsets_what_it_no_longer_sets() {
  install
  # A terminal inherits the login session's environment (Linux desktops, tmux): a setting turned
  # off since must not leave its variable behind; the user's own stay
  home_file .config/om818/config.sh 'om818_xdg_cargo=off'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" env --quiet
  run env OLD=1 CARGO_HOME=/old OM818_ENV_VARS='CARGO_HOME RUSTUP_HOME' sh -c '
    . "$HOME/'"$ENV_FILE"'"
    echo "cargo=${CARGO_HOME:-} rustup=${RUSTUP_HOME:-} old=$OLD"'
  assert_output_eq "cargo= rustup=${SANDBOX}/home/.local/share/rustup old=1"
  zsh_i 'print -r -- "$OM818_ENV_VARS"'
  if [[ " $OUTPUT " != *' RUSTUP_HOME '* || " $OUTPUT " == *' CARGO_HOME '* ]]; then
    fail "OM818_ENV_VARS: $OUTPUT"
  fi
}

function test_sandbox_only() {
  local cmd other="${SANDBOX}/other/om818/sandbox-only"
  # A command kept for sandboxes, for any program finding it on PATH (here sh, as an IDE would),
  # even from ~/.local/bin, which the environment puts in front of the rest
  home_file .config/om818/config.sh 'om818_sandbox_only=(claude)'
  home_file .local/bin/claude 'echo "claude $*"'
  chmod +x "${SANDBOX}/home/.local/bin/claude"
  install
  cmd='. "$HOME/'"$ENV_FILE"'"; claude hi'
  # (the machine running the tests may be a container itself, e.g. CI's Alpine job)
  if [[ ! -f /.dockerenv && ! -f /run/.containerenv ]]; then
    run sh -c "$cmd"
    assert_status 126
    assert_output_contains 'claude: not in a sandbox (drop, container): run it in one,'
    shell_i bash 'claude hi'
    assert_output_contains 'claude: not in a sandbox'
  fi
  run DROP_ENV=dev sh -c "$cmd"
  assert_output_eq 'claude hi'
  run container=podman sh -c "$cmd"
  assert_output_eq 'claude hi'
  # A distrobox shares the home folder: not a sandbox unless listed
  if [[ ! -f /.dockerenv && ! -f /run/.containerenv ]]; then
    run container=podman CONTAINER_ID=box sh -c "$cmd"
    assert_status 126
  fi
  run OM818_SANDBOX_ONLY=off sh -c "$cmd"
  assert_output_eq 'claude hi'
  # Another copy of the wrappers on PATH (e.g. another home's, mounted in a sandbox)
  mkdir -p -- "$other"
  # (-e: macOS's sed takes a -- after the script for a file name)
  sed -e "s|${SANDBOX}/home/|/home/other/|g" -- \
    "${SANDBOX}/home/.local/state/om818/sandbox-only/claude" >"${other}/claude"
  chmod +x "${other}/claude"
  RUN_TIMEOUT=5 run DROP_ENV=dev sh -c '. "$HOME/'"$ENV_FILE"'"
    PATH="'"$other"':$PATH"; claude hi'
  assert_output_eq 'claude hi'
  # Turned off: no wrapper left
  home_file .config/om818/config.sh ''
  run "${SANDBOX}/home/.local/share/om818/bin/om818" env --quiet
  run sh -c "$cmd"
  assert_output_eq 'claude hi'
}

function test_sandbox_wrapper_edge_cases() {
  local dir="${SANDBOX}/home/.local/state/om818/sandbox-only"
  home_file .config/om818/config.sh 'om818_sandbox_only=(. .. claude codex)'
  home_file .local/bin/claude 'echo "claude $*"'
  chmod +x "${SANDBOX}/home/.local/bin/claude"
  install
  # A listed command that isn't installed: not found, wherever it runs
  run sh -c '. "$HOME/'"$ENV_FILE"'"; codex'
  assert_status 127
  assert_output_eq 'codex: command not found'
  # Its own folder on PATH spelled another way: not taken for the real command (it would loop)
  RUN_TIMEOUT=5 run container=podman sh -c '. "$HOME/'"$ENV_FILE"'"
    PATH="$HOME/.local/state/om818/sandbox-only/:$PATH"; claude hi'
  assert_output_eq 'claude hi'
  # "." and ".." are no command names
  if [[ "$(ls -a -- "$dir")" != $'.\n..\nclaude\ncodex' ]]; then
    fail "wrappers: $(ls -a -- "$dir")"
  fi
}

function test_your_own_variables_win() {
  install
  # GOPATH set before oh-my-818 (e.g. in ~/.profile): kept, and never unset by a later environment
  run GOPATH=/mine sh -c '. "$HOME/'"$ENV_FILE"'"; echo "$GOPATH"'
  assert_output_eq '/mine'
  run GOPATH=/mine "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains 'left as you set them: GOPATH'
  # One session: the environment, then GOPATH's integration off and the environment again
  run GOPATH=/mine sh -c '. "$HOME/'"$ENV_FILE"'"
    echo om818_xdg_go=off >"$HOME/.config/om818/config.sh"
    "$HOME/.local/share/om818/bin/om818" env --quiet
    . "$HOME/'"$ENV_FILE"'"
    echo "$GOPATH"'
  assert_output_eq '/mine'
}

# ~/bin, where Fedora's profiles put it (and zsh no longer reads ~/.zprofile): on PATH, after
# ~/.local/bin. A folder the previous environment put in front, then no longer set (here go's,
# its setting turned off): gone once the new one is loaded by a new terminal, which inherits the
# login session's environment (OM818_PATH_FRONT exported with PATH), also from a terminal that
# loaded it again
function test_path_front_follows_the_settings() {
  mkdir -p -- "${SANDBOX}/home/bin" "${SANDBOX}/home/.local/bin"
  install
  # (the folders it puts in front too: they would go back in front on macOS, _om818_path_front)
  home_file new-terminal.sh '. "$HOME/'"$ENV_FILE"'"; echo "${PATH}|${OM818_PATH_FRONT}:"'
  run sh -c '. "$HOME/'"$ENV_FILE"'"; . "$HOME/'"$ENV_FILE"'"; echo "$PATH"
    printf "%s\n" om818_xdg_go=off >"$HOME/.config/om818/config.sh"
    "$HOME/.local/share/om818/bin/om818" env --quiet
    sh "$HOME/new-terminal.sh"'
  if [[ "${OUTPUT%%$'\n'*}" != *"${SANDBOX}/home/.local/bin:${SANDBOX}/home/bin:"* ]]; then
    fail "no ~/.local/bin then ~/bin: ${OUTPUT}"
  fi
  if [[ "${OUTPUT%%$'\n'*}" != *"/go/bin:"* ]]; then fail "no go/bin first: ${OUTPUT}"; fi
  if [[ "${OUTPUT#*$'\n'}" == *"/go/bin:"* ]]; then fail "go/bin left: ${OUTPUT}"; fi
}

# A folder put in front of the environment's (a virtualenv that a child shell inherits, e.g.
# pipenv shell, or a zsh script run from it): still in front once the environment is loaded again,
# also of the folders env.d/ adds (pruned after them, else taken out and put back in front)
function test_path_front_keeps_what_came_after() {
  install
  home_file .config/om818/env.d/10-path.sh 'om818_path_prepend /own-bin'
  run sh -c '. "$HOME/'"$ENV_FILE"'"; PATH="/venv/bin:$PATH"; . "$HOME/'"$ENV_FILE"'"; echo "$PATH"'
  if [[ "$OUTPUT" != /venv/bin:* ]]; then fail "the virtualenv no longer first: ${OUTPUT}"; fi
  assert_output_contains ':/own-bin:'
}

# env.d/ no longer setting a folder: gone when the environment added it, kept when it was on PATH
# already (from the system or the profile, e.g. brew shellenv)
function test_path_keeps_a_folder_it_did_not_add() {
  install
  home_file .config/om818/env.d/10-path.sh 'om818_path_prepend /sys-bin
om818_path_prepend /own-bin'
  run sh -c 'PATH="/sys-bin:$PATH"; . "$HOME/'"$ENV_FILE"'"
    rm -- "$HOME/.config/om818/env.d/10-path.sh"; . "$HOME/'"$ENV_FILE"'"; echo ":$PATH:"'
  assert_output_contains ':/sys-bin:'
  assert_output_not_contains ':/own-bin:'
}

run_tests "$@"
