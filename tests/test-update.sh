#!/usr/bin/env bash
# shellcheck disable=SC2016 # shell code to run, in single quotes on purpose
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of updates: the daily check, the notice, update, rollback, read-only installs.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

OM818='.local/share/om818/bin/om818'

function test_check_then_notice() {
  install
  run "${SANDBOX}/home/${OM818}" check
  assert_status 0
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'

  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'latest=v0.2.0'
  zsh_i 'print -r -- ready'
  assert_output_eq 'oh-my-818 v0.2.0 is available (you have v0.1.0): om818 update
ready'
}

function test_update_and_rollback() {
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'v0.1.0 -> v0.2.0'
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.2.0'
  assert_file_contains .local/state/om818/env.sh 'om818 v0.2.0'
  run "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'up to date (v0.2.0)'

  run "${SANDBOX}/home/${OM818}" rollback
  assert_output_contains 'v0.2.0 -> v0.1.0'
  # Once: a second one would go forward again
  run "${SANDBOX}/home/${OM818}" rollback
  assert_status 1
  assert_output_contains 'no previous release'
  # The release left is skipped until a newer one
  run "${SANDBOX}/home/${OM818}" check
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
  add_release v0.3.0
  run "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'latest=v0.3.0'
}

function test_auto_update() {
  home_file .config/om818/config.sh 'om818_update=auto'
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  # Not the shells om818 starts to inspect the setup (status's bash probe)
  run "${SANDBOX}/home/${OM818}" status
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
  # A starting shell updates from what the check fetched: it never waits on the network
  git_ -C "${SANDBOX}/home/.local/share/om818" remote set-url origin "${SANDBOX}/nowhere"
  zsh_i 'print -r -- ready'
  assert_output_contains 'v0.1.0 -> v0.2.0'
}

function test_update_with_edited_files() {
  install
  add_release v0.2.0
  printf '# mine\n' >>"${SANDBOX}/home/.local/share/om818/defaults.sh"
  run "${SANDBOX}/home/${OM818}" update
  assert_status 1
  assert_output_contains "files of ~/.local/share/om818 were edited, so it can't update"
}

function test_one_update_at_a_time() {
  local fd
  if ! command -v flock >/dev/null 2>&1; then return 0; fi
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  # Another one running (e.g. terminals opening at once): a shell's update gives way quietly, at
  # once (it would otherwise wait 30 s). (The commands don't get the test's open file: a process
  # they leave running would hold the lock)
  exec {fd}>>"${SANDBOX}/home/.local/state/om818/lock"
  flock -n "$fd"
  RUN_TIMEOUT=5 run "${SANDBOX}/home/${OM818}" update --no-fetch {fd}>&-
  assert_status 0
  assert_output_eq ''
  run "${SANDBOX}/home/${OM818}" version {fd}>&-
  assert_output_eq 'v0.1.0'
  # A terminal finding config.sh changed doesn't wait for it either (the next one regenerates)
  printf 'om818_prompt_clock=off\n' >>"${SANDBOX}/home/.config/om818/config.sh"
  RUN_TIMEOUT=5 zsh_i 'print -r -- ready' {fd}>&-
  assert_status 0
  assert_output_contains 'ready'
  # Its owner gone, however it ended: free
  exec {fd}>&-
  RUN_TIMEOUT=5 run "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_output_contains 'v0.1.0 -> v0.2.0'
  # A process the command started and left running doesn't hold it (here from config.sh, which
  # every command reads; a tool's daemon, one from ~/.bashrc…)
  printf '(sleep 20 >/dev/null 2>&1 &)\n' >>"${SANDBOX}/home/.config/om818/config.sh"
  run "${SANDBOX}/home/${OM818}" env
  assert_status 0
  RUN_TIMEOUT=5 run "${SANDBOX}/home/${OM818}" env
  assert_status 0
}

# Where flock is missing (macOS): the lock folder
function test_one_update_at_a_time_without_flock() {
  local lock="${SANDBOX}/home/.local/state/om818/lock.d" path="${SANDBOX}/bin:${SANDBOX}/sysbin"
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  sysbin_without_flock
  mkdir -p -- "$lock"
  printf '%s %s\n' "$BASHPID" "$(uname -n)" >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_status 0
  assert_output_eq ''
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
  printf 'om818_prompt_clock=off\n' >>"${SANDBOX}/home/.config/om818/config.sh"
  RUN_TIMEOUT=5 zsh_i PATH="$path" 'print -r -- ready'
  assert_status 0
  assert_output_contains 'ready'
  # Owned by a process of another host (a home shared between machines): can't be checked, kept
  printf '999999999 elsewhere\n' >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" update --no-fetch
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
  # Owned by a live process for 10 minutes (its pid reused after a reboot): taken over
  printf '%s %s 1\n' "$BASHPID" "$(uname -n)" >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_output_contains 'v0.1.0 -> v0.2.0'
  if [[ -e "$lock" ]]; then fail "lock folder left: $(ls -la -- "$lock")"; fi
  # Without a start time (an older release's), its folder 10 minutes old: taken over
  run "${SANDBOX}/home/${OM818}" rollback
  mkdir -p -- "$lock"
  printf '%s %s\n' "$BASHPID" "$(uname -n)" >"${lock}/owner"
  touch -t 202001010000 -- "$lock"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_output_contains 'v0.1.0 -> v0.2.0'
  # Its owner gone (killed, its terminal closed): taken over
  run "${SANDBOX}/home/${OM818}" rollback
  mkdir -p -- "$lock"
  printf '999999999 %s\n' "$(uname -n)" >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_output_contains 'v0.1.0 -> v0.2.0'
}

# A state folder that can't be written (its lock file there already): an error at once, and
# terminals still start, quietly
function test_lock_cannot_be_made() {
  local path
  install
  sysbin_without_flock
  printf 'om818_prompt_clock=off\n' >>"${SANDBOX}/home/.config/om818/config.sh"
  chmod a-w "${SANDBOX}/home/.local/state/om818"
  for path in "${SANDBOX}/bin:${TEST_DIR}/sysbin" "${SANDBOX}/bin:${SANDBOX}/sysbin"; do
    RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" env
    assert_status 1
    assert_output_contains 'cannot write ~/.local/state/om818'
    RUN_TIMEOUT=5 shell_i zsh PATH="$path" 'print -r -- ready'
    assert_output_eq 'ready'
  done
  chmod u+w "${SANDBOX}/home/.local/state/om818"
}

# $SANDBOX/sysbin: $TEST_DIR/sysbin without flock (as on macOS)
function sysbin_without_flock() {
  local tool
  mkdir -p -- "${SANDBOX}/sysbin"
  for tool in "${TEST_DIR}/sysbin"/*; do
    if [[ "$tool" != */flock ]]; then ln -s -- "$(readlink -- "$tool")" "${SANDBOX}/sysbin/"; fi
  done
}

function test_update_cut_short() {
  local lock="${SANDBOX}/home/.local/state/om818/lock.d"
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  # Closed after its checkout, before its install (here: the ~/.zshenv line it adds back)
  git_ -C "${SANDBOX}/home/.local/share/om818" -c advice.detachedHead=false checkout -q v0.2.0
  : >"${SANDBOX}/home/.local/state/om818/install-pending"
  rm -f -- "${SANDBOX}/home/.zshenv"
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains \
    '! update       an update stopped before its end: om818 update finishes it'
  run "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_status 0
  assert_file_contains .zshenv '# om818'
  if [[ -e "${SANDBOX}/home/.local/state/om818/install-pending" ]]; then fail 'still pending'; fi
  # The daily check finishes it too, under the lock: while another command holds it (e.g. the
  # update itself still running), it gives way at once, no second checkout meanwhile
  git_ -C "${SANDBOX}/home/.local/share/om818" rev-parse 'v0.1.0^{commit}' \
    >"${SANDBOX}/home/.local/state/om818/install-pending"
  rm -f -- "${SANDBOX}/home/.zshenv"
  sysbin_without_flock
  mkdir -- "$lock"
  printf '%s %s\n' "$BASHPID" "$(uname -n)" >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="${SANDBOX}/bin:${SANDBOX}/sysbin" "${SANDBOX}/home/${OM818}" check
  if [[ "$(git_ -C "${SANDBOX}/home/.local/share/om818" describe --tags)" != v0.2.0 ]]; then
    fail 'checked out without the lock'
  fi
  assert_status 0
  rm -rf -- "$lock"
  run "${SANDBOX}/home/${OM818}" check
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
  assert_file_contains .zshenv '# om818'
  # Cut short during the checkout itself: the tree mixes both versions (here, v0.1.0 checked out
  # with a file already changed): the next update checks it out again, no "edited" files
  git_ -C "${SANDBOX}/home/.local/share/om818" -c advice.detachedHead=false checkout -q v0.1.0
  git_ -C "${SANDBOX}/home/.local/share/om818" rev-parse 'v0.2.0^{commit}' \
    >"${SANDBOX}/home/.local/state/om818/install-pending"
  printf '# half-way\n' >>"${SANDBOX}/home/.local/share/om818/defaults.sh"
  run "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_status 0
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.2.0'
  if grep -q 'half-way' "${SANDBOX}/home/.local/share/om818/defaults.sh"; then fail 'tree mixed'; fi
  # The same repaired by `om818 install` (what status and the docs suggest for other rows)
  git_ -C "${SANDBOX}/home/.local/share/om818" -c advice.detachedHead=false checkout -q v0.1.0
  git_ -C "${SANDBOX}/home/.local/share/om818" rev-parse 'v0.2.0^{commit}' \
    >"${SANDBOX}/home/.local/state/om818/install-pending"
  printf '# half-way\n' >>"${SANDBOX}/home/.local/share/om818/defaults.sh"
  run "${SANDBOX}/home/${OM818}" install
  assert_status 0
  if [[ -n "$(git_ -C "${SANDBOX}/home/.local/share/om818" status --porcelain)" ]]; then
    fail 'tree mixed after om818 install'
  fi
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.2.0'
  # A commit no longer there (a tag deleted upstream, then gc): dropped, not an error each time
  printf '%040d\n' 0 >"${SANDBOX}/home/.local/state/om818/install-pending"
  run "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_status 0
  if [[ -e "${SANDBOX}/home/.local/state/om818/install-pending" ]]; then fail 'still pending'; fi
}

# A rollback cut short during its checkout: once finished, it is a rollback (no previous release,
# the release left not announced again), not an update back
function test_rollback_cut_short() {
  local fake="${SANDBOX}/fake-git"
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" update
  mkdir -p -- "$fake"
  printf '#!/bin/sh\ncase " $* " in *" checkout "*) exit 1 ;; esac\nexec %q "$@"\n' \
    "$(command -v git)" >"${fake}/git"
  chmod +x -- "${fake}/git"
  run PATH="${fake}:${SANDBOX}/bin:${TEST_DIR}/sysbin" "${SANDBOX}/home/${OM818}" rollback
  assert_file_contains .local/state/om818/update 'skip=v0.2.0'
  run "${SANDBOX}/home/${OM818}" rollback
  assert_output_contains 'no previous release'
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
}

# An update cut short during its checkout, then a rollback: the update is finished first (its
# mixed tree would be refused as edited), then rolled back
function test_rollback_after_an_update_cut_short() {
  local dir="${SANDBOX}/home/.local/share/om818" state="${SANDBOX}/home/.local/state/om818"
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  # (as release_checkout leaves it: the current commit as previous, the target pending)
  git_ -C "$dir" rev-parse HEAD >"${state}/previous"
  git_ -C "$dir" rev-parse 'v0.2.0^{commit}' >"${state}/install-pending"
  printf '# half-way\n' >>"${dir}/defaults.sh"
  run "${SANDBOX}/home/${OM818}" rollback
  assert_status 0
  assert_output_contains 'v0.2.0 -> v0.1.0'
  if [[ -n "$(git_ -C "$dir" status --porcelain)" ]]; then fail 'tree mixed'; fi
}

# An update cut short, then the install line asking for another version (OM818_REF): that
# version wins (om818 install would otherwise finish the update)
function test_install_line_ref_over_an_update_cut_short() {
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  git_ -C "${SANDBOX}/home/.local/share/om818" rev-parse 'v0.2.0^{commit}' \
    >"${SANDBOX}/home/.local/state/om818/install-pending"
  install OM818_REF=v0.1.0
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
}

function test_read_only_install() {
  install
  # A release known (e.g. found by the host): shells don't announce it, they can't update
  printf 'checked=%s\ncurrent=v0.1.0\nlatest=v0.2.0\nskip=\n' "$(date +%s)" \
    >"${SANDBOX}/home/.local/state/om818/update"
  chmod -R a-w "${SANDBOX}/home/.local/share/om818"
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
  run "${SANDBOX}/home/${OM818}" update
  assert_status 1
  assert_output_contains 'read-only'
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'read-only install'
  chmod -R u+w "${SANDBOX}/home/.local/share/om818"
}

function test_pre_releases_are_skipped() {
  # git's version sort puts v0.2.0-rc1 after v0.1.0 (and after v0.2.0): never taken as a release.
  # (Its commit is also main's newest, which isn't a release either: branches never run)
  add_release v0.2.0-rc1
  install
  assert_output_contains 'oh-my-818 v0.1.0 is installed'
  run "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'up to date (v0.1.0)'
}

function test_update_sets_up_the_new_version() {
  install
  # A release adding an integration: the update's environment has it (generated by the new code)
  mkdir -p -- "${FIXTURE}/integrations/newtool"
  printf '%s\n' 'om818_integration_env() { env_set NEWTOOL 1; }' \
    >"${FIXTURE}/integrations/newtool/integration.sh"
  printf 'om818_newtool=auto\n' >>"${FIXTURE}/defaults.sh"
  git_ -C "$FIXTURE" add -A
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'v0.1.0 -> v0.2.0'
  assert_file_contains .local/state/om818/env.sh "export NEWTOOL='1'"
}

function test_ignores_git_variables_of_another_repository() {
  # As exported by vcsh or yadm: git must still act on oh-my-818's checkout
  local other="${SANDBOX}/other"
  install
  add_release v0.2.0
  git_ init -q -b main "$other"
  git_ -C "$other" commit -q --allow-empty -m other
  git_ -C "$other" tag v9.0.0
  run GIT_DIR="${other}/.git" GIT_WORK_TREE="$other" "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'latest=v0.2.0'
  run GIT_DIR="${other}/.git" GIT_WORK_TREE="$other" "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'v0.1.0 -> v0.2.0'
  if [[ "$(git_ -C "$other" rev-parse HEAD)" != "$(git_ -C "$other" rev-parse v9.0.0)" ]]; then
    fail 'the other repository changed'
  fi
}

function test_repair_updates_the_notice() {
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  # Repaired onto the release the notice announces: no notice any more
  install OM818_REF=v0.2.0
  assert_file_contains .local/state/om818/update 'current=v0.2.0'
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
}

function test_follows_deleted_tags() {
  # A release tag pushed by mistake, then deleted on GitHub: no longer the latest
  install
  add_release v9.0.0
  run "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'latest=v9.0.0'
  git_ -C "$FIXTURE" tag -d v9.0.0 >/dev/null
  run "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'latest='
  if grep -q 'latest=v9' "${SANDBOX}/home/.local/state/om818/update"; then fail 'still latest'; fi
}

function test_checks_once_a_day() {
  local update="${SANDBOX}/home/.local/state/om818/update" hour_ago
  # (Homebrew's git, first on PATH with a system Homebrew, would run instead of the fake one)
  home_file .config/om818/config.sh 'om818_homebrew=off'
  install
  add_release v0.2.0
  # git's fetches, logged (the checks run in the background: counted once the second one is done)
  fake_tool git 'case " $* " in *" fetch "*) echo fetch >>"'"${SANDBOX}"'/fetches" ;; esac
exec "'"${TEST_DIR}"'/sysbin/git" "$@"'
  # Checked an hour ago: a new shell doesn't check again (it would fetch at every start; a check
  # records its time first)
  hour_ago="$(($(date +%s) - 3600))"
  printf 'checked=%s\ncurrent=v0.1.0\nlatest=\nskip=\n' "$hour_ago" >"$update"
  zsh_i ':'
  sleep 1
  assert_file_contains .local/state/om818/update "checked=${hour_ago}"
  # A day ago: checked, in the background
  printf 'checked=%s\ncurrent=v0.1.0\nlatest=\nskip=\n' "$(($(date +%s) - 90000))" >"$update"
  zsh_i ':'
  if ! wait_for grep -q 'latest=v0.2.0' "$update"; then fail 'not checked'; fi
  sleep 1
  assert_count ../fetches fetch 1
}

function test_update_shows_what_changed() {
  install
  add_release v0.2.0
  # The changelog of v0.3.0: what changed since v0.1.0, the version installed (v0.2.0's and
  # v0.3.0's), not before
  printf '%s\n' '# Changelog' '' '## v0.3.0' '' '- Third.' '' '## v0.2.0' '' '- Second.' '' \
    '## v0.1.0' '' '- First.' >"${FIXTURE}/CHANGELOG.md"
  git_ -C "$FIXTURE" add CHANGELOG.md
  add_release v0.3.0
  run "${SANDBOX}/home/${OM818}" update
  assert_output_contains 'v0.1.0 -> v0.3.0'
  assert_output_contains 'What changed:
  v0.3.0
    - Third.
  v0.2.0
    - Second.'
  assert_output_not_contains 'First.'
}

function test_command_arguments() {
  install
  add_release v0.2.0
  # --help shows the help, not an update; a mistyped option stops
  run "${SANDBOX}/home/${OM818}" update --help
  assert_output_contains 'usage: om818 <command>'
  run "${SANDBOX}/home/${OM818}" update --no-fetsh
  assert_status 2
  assert_output_eq 'error: om818 update: unknown argument: --no-fetsh (om818 help)'
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
}

function test_update_offline() {
  install
  git_ -C "${SANDBOX}/home/.local/share/om818" remote set-url origin "${SANDBOX}/nowhere"
  run "${SANDBOX}/home/${OM818}" update
  assert_status 1
  assert_output_eq "error: cannot reach ${SANDBOX}/nowhere (offline?): still on v0.1.0"
  # The daily check records it, for status
  run "${SANDBOX}/home/${OM818}" check
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'the last check failed (offline?)'
}

# The lock file is private: another user able to open it could hold it
function test_lock_file_is_private() {
  if ! command -v flock >/dev/null 2>&1; then return 0; fi
  install
  if [[ "$(ls -l -- "${SANDBOX}/home/.local/state/om818/lock")" != -rw-------* ]]; then
    fail "lock: $(ls -l -- "${SANDBOX}/home/.local/state/om818/lock")"
  fi
}

# flock failing otherwise than "busy" (e.g. a home on NFS without locks): the lock folder instead,
# its owner file naming the pid, the host and the start time
function test_flock_error_uses_the_folder() {
  local pid host since
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  fake_tool flock 'exit 69'
  printf '%s\n' 'f="$HOME/.local/state/om818/lock.d/owner"' \
    'if [ -e "$f" ]; then cp -- "$f" ~/owner; fi' >>"${SANDBOX}/home/.config/om818/config.sh"
  RUN_TIMEOUT=5 run "${SANDBOX}/home/${OM818}" update --no-fetch
  assert_output_contains 'v0.1.0 -> v0.2.0'
  if [[ -e "${SANDBOX}/home/.local/state/om818/lock.d" ]]; then fail 'lock folder left'; fi
  read -r pid host since <"${SANDBOX}/home/owner"
  if [[ ! "$pid" =~ ^[0-9]+$ || "$host" != "$(uname -n)" || ! "$since" =~ ^[0-9]+$ ]]; then
    fail "owner: $(<"${SANDBOX}/home/owner")"
  fi
}

# An update killed right after its checkout: install-pending is already there (status says so,
# the next command finishes it)
function test_update_killed_after_its_checkout() {
  local pending
  install
  add_release v0.2.0
  run "${SANDBOX}/home/${OM818}" check
  fake_tool git 'if [ "${5:-}" = checkout ]; then
  "'"${TEST_DIR}"'/sysbin/git" "$@"
  kill -KILL "$PPID"
fi
exec "'"${TEST_DIR}"'/sysbin/git" "$@"'
  run "${SANDBOX}/home/${OM818}" update --no-fetch
  rm -f -- "${SANDBOX}/bin/git"
  # (the commit to check out again: the checkout may have stopped half-way)
  pending="$(<"${SANDBOX}/home/.local/state/om818/install-pending")"
  if [[ "$pending" != "$(git_ -C "$FIXTURE" rev-parse 'v0.2.0^{commit}')" ]]; then
    fail "install-pending: ${pending}"
  fi
  run "${SANDBOX}/home/${OM818}" status
  assert_output_contains 'an update stopped before its end'
  run "${SANDBOX}/home/${OM818}" update --no-fetch
  run "${SANDBOX}/home/${OM818}" status
  assert_output_not_contains 'an update stopped before its end'
  # The release it left, kept before the checkout: a rollback goes back to it
  run "${SANDBOX}/home/${OM818}" rollback
  run "${SANDBOX}/home/${OM818}" version
  assert_output_eq 'v0.1.0'
}

# A lock folder taken over while its first owner still runs (10 minutes on): that owner, as it
# ends, leaves the new owner's lock in place
function test_lock_folder_taken_over_is_kept() {
  install
  fake_tool flock 'exit 69'
  printf 'if [ -n "${OM818_LOCKED:-}" ] && [ -d "$HOME/.local/state/om818/lock.d" ]; then
  echo "%s $(uname -n) $(date +%%s)" >"$HOME/.local/state/om818/lock.d/owner"
fi\n' "$BASHPID" >>"${SANDBOX}/home/.config/om818/config.sh"
  run "${SANDBOX}/home/${OM818}" env
  assert_status 0
  if [[ ! -d "${SANDBOX}/home/.local/state/om818/lock.d" ]]; then
    fail "the new owner's lock removed"
  fi
}

# A rollback during the daily check's fetch (its skip= recorded meanwhile): kept, the release left
# isn't announced again
function test_check_keeps_a_rollback() {
  install
  add_release v0.2.0
  fake_tool git 'case " $* " in *" fetch "*)
  sed -i.bak "s/^skip=.*/skip=v0.2.0/" "$HOME/.local/state/om818/update" ;; esac
exec "'"${TEST_DIR}"'/sysbin/git" "$@"'
  run "${SANDBOX}/home/${OM818}" check
  assert_file_contains .local/state/om818/update 'skip=v0.2.0'
  if grep -q '^latest=v0.2.0' "${SANDBOX}/home/.local/state/om818/update"; then
    fail 'the release left announced again'
  fi
}

# A host name holding a blank: the lock folder's owner keeps it as one word, so a command's
# lock goes with it (else the next commands are refused for 10 minutes), and a dead owner's is
# taken over
function test_lock_with_a_blank_in_the_host_name() {
  local path="${SANDBOX}/bin:${SANDBOX}/sysbin" lock="${SANDBOX}/home/.local/state/om818/lock.d"
  install
  sysbin_without_flock
  fake_tool uname 'if [ "${1:-}" = -n ]; then echo "my host"; else
  exec '"${TEST_DIR}/sysbin/uname"' "$@"
fi'
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" env --quiet
  assert_status 0
  if [[ -e "$lock" ]]; then fail "lock folder left: $(<"${lock}/owner")"; fi
  mkdir -- "$lock"
  printf '999999999 my_host %s\n' "$(date +%s)" >"${lock}/owner"
  RUN_TIMEOUT=5 run PATH="$path" "${SANDBOX}/home/${OM818}" env --quiet
  assert_status 0
}

run_tests "$@"
