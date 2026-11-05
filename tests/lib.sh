# shellcheck shell=bash
# Shared by the test scripts (sourced): a sandbox per test, a fixture repository, assertions.
#
# The fixture is a git repository holding a copy of the working tree (committed, tagged v0.1.0),
# so tests install and update from it like from GitHub. Each test gets a fresh sandbox:
#   $SANDBOX/home  HOME
#   $SANDBOX/bin   fake tools and the tests' bash, first on PATH
#   $SANDBOX/fixture  the fixture (tests may add releases to it)
# then on PATH, $TEST_DIR/sysbin: links to the system's commands the code needs (SYSTEM_TOOLS),
# and nothing else: tools installed on the machine (mise, podman, gh…) don't change the results.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

TEST_DIR=''         # temporary directory of this run
FIXTURE=''          # the fixture repository of the current test (a copy of the run's)
SANDBOX=''          # sandbox of the current test
OUTPUT='' STATUS='' # output (stdout and stderr) and exit code of the last `run`
SHELL_I=''          # the shell of the last shell_i (named in failures)
TMUX_SOCKET=''      # the current test's tmux socket: short (macOS: 103 bytes at most)
# The temporary install's folder names end with the PID namespace when it isn't the host's (in a
# container, as this sandbox may be): "-<its number>", else nothing (install.sh temp_folder)
TEMP_NS="$(ls -Ldi /proc/self/ns/pid 2>/dev/null)" || TEMP_NS=''
TEMP_NS="${TEMP_NS%% *}"
case "$TEMP_NS" in '' | 4026531836 | *[!0-9]*) TEMP_NS='' ;; *) TEMP_NS="-${TEMP_NS}" ;; esac
RUN_TIMEOUT=60 # seconds a command may run
# A UTF-8 locale for the shells: C.UTF-8 where it exists (macOS has none)
TEST_LANG='C.UTF-8'
if [[ "$(uname -s)" == 'Darwin' ]]; then TEST_LANG='en_US.UTF-8'; fi
# Each command in its own session, killed with all it left behind once the test ends: setsid
# (Linux; it doesn't fork in a background subshell, so the command's pid is the session's id),
# else perl's setsid (macOS, which has no setsid command)
SETSID=()
if command -v pkill >/dev/null 2>&1; then
  if command -v setsid >/dev/null 2>&1; then
    SETSID=(setsid)
  elif command -v perl >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # perl code
    SETSID=(perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die "$ARGV[0]: $!\n"')
  fi
fi

# The system's commands the code and the tests use (those missing on a system are skipped, e.g.
# setsid on macOS)
SYSTEM_TOOLS=(
  sh zsh git
  awk basename cat chmod cmp cp cut date dirname env expr find flock getconf grep head id iconv ln
  ls mkdir mkfifo mktemp mv od printf ps readlink rm rmdir sed setsid sleep sort sw_vers tail tar
  tee test timeout tmux touch tr true false uname uniq wc xargs
)

### Running

# Run the test_* functions of the test script (or the given ones), each in a fresh sandbox
# usage: run_tests [<test>...]
function run_tests() {
  local test out status failed=0 n=0
  local -a tests

  if [[ $# -gt 0 ]]; then
    tests=("$@")
  else
    out="$(grep -o '^function test_[A-Za-z0-9_]*' -- "$0")"
    mapfile -t tests <<<"${out//function /}"
  fi

  TEST_DIR="$(mktemp -d)"
  # (never fatal, like each test's: errexit would make a process still writing fail the whole run)
  trap 'rm -rf -- "$TEST_DIR" || true' EXIT
  # (the runners': private folders the temporary install checks, e.g. not group-writable)
  umask 022
  limit_processes
  make_fixture
  make_sysbin

  for test in "${tests[@]}"; do
    SANDBOX="${TEST_DIR}/${test}"
    n=$((n + 1))
    TMUX_SOCKET="${TEST_DIR}/tmux.${n}"
    SHELL_I=''
    mkdir -p -- "${SANDBOX}/home" "${SANDBOX}/bin"
    FIXTURE="${SANDBOX}/fixture"
    cp -a -- "${TEST_DIR}/fixture" "$FIXTURE"
    # The bash running the tests (4.4+), first on PATH: on macOS, /bin/bash is 3.2
    ln -s -- "$BASH" "${SANDBOX}/bin/bash"
    # Not in a condition: errexit would be off inside the subshell
    set +e
    (
      set -Eeuo pipefail
      "$test"
    )
    status="$?"
    set -e
    # (a tmux server runs in its own session: stopped by its socket)
    if [[ -S "$TMUX_SOCKET" ]]; then
      "${TEST_DIR}/sysbin/tmux" -S "$TMUX_SOCKET" kill-server 2>/dev/null || true
    fi
    kill_leftovers
    # Never fatal: a test may leave read-only files, or a process still writing (retried once)
    chmod -R u+w "$SANDBOX" 2>/dev/null || true
    rm -rf -- "$SANDBOX" 2>/dev/null || { sleep 1 && rm -rf -- "$SANDBOX" 2>/dev/null; } || true
    if [[ "$status" -eq 0 ]]; then
      printf 'ok   %s\n' "$test"
    else
      printf 'FAIL %s\n' "$test"
      failed=$((failed + 1))
    fi
  done
  if [[ "$failed" -ne 0 ]]; then
    printf '%s: %d failed\n' "$(basename -- "$0")" "$failed"
    return 1
  fi
}

# Commit a copy of the working tree into the fixture repository, tagged v0.1.0
function make_fixture() {
  local dir="${TEST_DIR}/fixture"
  mkdir -p -- "$dir"
  tar -C "$ROOT_DIR" --exclude=./.git --exclude=./.local -cf - . | tar -C "$dir" -xf -
  git_ -C "$dir" init -q -b main
  git_ -C "$dir" add -A
  git_ -C "$dir" commit -qm 'fixture'
  git_ -C "$dir" tag v0.1.0
}

# Cap the processes the tests can start: a runaway (e.g. a shell whose command_not_found handler
# calls itself) fails to fork past this, instead of filling the machine's memory. The limit counts
# all of the user's processes, so it is the current count plus a margin; only the tests' processes
# get it
function limit_processes() {
  local n hard out
  # (busybox's ps has no -u: no limit there)
  if ! out="$(ps -u "$(id -u)" -o pid= 2>/dev/null)"; then return 0; fi
  n="$(wc -l <<<"$out")"
  hard="$(ulimit -H -u)"
  if [[ "$hard" != 'unlimited' && "$((n + 500))" -gt "$hard" ]]; then return 0; fi
  ulimit -S -u "$((n + 500))"
}

# Kill what a test left running (e.g. the shells' background jobs, a runaway): each command ran
# in its own session (run), whose processes are stopped first, so that none can fork meanwhile,
# then killed (pkill -s). The sessions are listed in $SANDBOX/.sessions (the test ran in a
# subshell)
function kill_leftovers() {
  local sid _
  if [[ ! -f "${SANDBOX}/.sessions" ]]; then return 0; fi
  while IFS= read -r sid; do
    # (nothing left, the usual case: no scan of every process)
    if ! kill -0 -- "-${sid}" 2>/dev/null; then continue; fi
    # Without ps -s (busybox, BSD): a few rounds, blind (macOS has no pkill -s either: only the
    # session's first process group, where a shell without job control keeps its background jobs)
    if ! ps -o stat= -s "$sid" >/dev/null 2>&1; then
      for _ in 1 2 3; do
        pkill -STOP -s "$sid" 2>/dev/null || true
        pkill -KILL -s "$sid" 2>/dev/null || true
        kill -KILL -- "-${sid}" 2>/dev/null || true
      done
      continue
    fi
    for _ in {1..50}; do
      # (zombies aside: dead, they only wait for their parent; pgrep counts them)
      # shellcheck disable=SC2009
      if ! ps -o stat= -s "$sid" 2>/dev/null | grep -qv '^Z'; then break; fi
      pkill -STOP -s "$sid" 2>/dev/null || true
      pkill -KILL -s "$sid" 2>/dev/null || true
    done
  done <"${SANDBOX}/.sessions"
}

# Link the system's commands of SYSTEM_TOOLS into $TEST_DIR/sysbin
function make_sysbin() {
  local tool path
  mkdir -p -- "${TEST_DIR}/sysbin"
  for tool in "${SYSTEM_TOOLS[@]}"; do
    # (Homebrew's last: on macOS, tmux)
    if ! path="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin &&
      command -v -- "$tool")"; then
      continue
    fi
    if [[ "$path" != /* ]]; then continue; fi # a builtin
    ln -s -- "$path" "${TEST_DIR}/sysbin/${tool}"
  done
}

# git without the user's config (signing, hooks), with a fixed identity
function git_() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
    git "$@"
}

# Add a release to the fixture: a commit changing a file, tagged
# usage: add_release <tag>
function add_release() {
  printf '%s\n' "$1" >"${FIXTURE}/.release"
  git_ -C "$FIXTURE" add .release
  git_ -C "$FIXTURE" commit -qm "release $1"
  git_ -C "$FIXTURE" tag "$1"
}

# Run a command in the sandbox's clean environment, capturing OUTPUT and STATUS (never fails).
# Its output goes through a file, not a pipe: a process it leaves in the background (a shell's
# background job, a runaway) can't keep the test waiting. Killed after RUN_TIMEOUT seconds.
# usage: run [VAR=value...] <command> [<args>...]
function run() {
  local out="${SANDBOX}/.output" pid watchdog
  local -a vars=()
  while [[ $# -gt 0 && "$1" == *=* ]]; do
    vars+=("$1")
    shift
  done
  (
    cd -- "$SANDBOX" && exec "${SETSID[@]}" env -i \
      HOME="${SANDBOX}/home" \
      PATH="${SANDBOX}/bin:${TEST_DIR}/sysbin" \
      TERM=xterm-256color \
      LANG="$TEST_LANG" \
      USER=tester \
      SHELL=/bin/zsh \
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_CONFIG_NOSYSTEM=1 \
      OM818_NO_DOWNLOAD=1 \
      OM818_REPO="$FIXTURE" \
      TESTS_DIR="${ROOT_DIR}/tests" \
      "${vars[@]}" "$@"
  ) >"$out" 2>&1 &
  pid="$!"
  if [[ "${#SETSID[@]}" -gt 0 ]]; then printf '%s\n' "$pid" >>"${SANDBOX}/.sessions"; fi
  # (the trap ends its sleep with it: no sleep left behind for each command)
  (
    sleep "$RUN_TIMEOUT" &
    trap 'kill "$!" 2>/dev/null; exit 0' TERM
    wait "$!"
    printf 'run: killed after %s s\n' "$RUN_TIMEOUT" >>"$out"
    kill -KILL "$pid" 2>/dev/null
  ) &
  watchdog="$!"
  STATUS=0
  # (stderr: bash's notice for a command it killed)
  { wait "$pid" || STATUS="$?"; } 2>/dev/null
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" || true
  OUTPUT="$(<"$out")"
}

# Install oh-my-818 in the sandbox from the fixture
# usage: install [VAR=value...]
function install() {
  run "$@" sh "${FIXTURE}/install.sh"
  assert_status 0
}

# Run an interactive zsh or bash in the sandbox, with the given code (valid in both shells for
# the tests running it in each: `source "$TESTS_DIR/plain.$om818_shell"` gives print_prompt)
# usage: shell_i zsh|bash [VAR=value...] <code>
function shell_i() {
  SHELL_I="$1"
  shift
  "${SHELL_I}_i" "$@"
}

# Run an interactive zsh in the sandbox, with the given code. Not the system's /etc/zshrc (e.g.
# Fedora's fixes the locale): the tests must not depend on the machine's startup files (zsh always
# reads /etc/zshenv, which only sets basics where it exists)
# usage: zsh_i [VAR=value...] <code>
function zsh_i() {
  local -a vars=()
  while [[ $# -gt 1 && "$1" == *=* ]]; do
    vars+=("$1")
    shift
  done
  run "${vars[@]}" zsh --no-globalrcs -i -c "$1"
}

# Run an interactive bash in the sandbox, with the given code (without the job control warnings
# of a shell that has no terminal). Only ~/.bashrc: Debian's and Ubuntu's bash would also read the
# system's /etc/bash.bashrc
# usage: bash_i [VAR=value...] <code>
function bash_i() {
  local -a vars=()
  local line out=''
  while [[ $# -gt 1 && "$1" == *=* ]]; do
    vars+=("$1")
    shift
  done
  run "${vars[@]}" bash --rcfile "${SANDBOX}/home/.bashrc" -i -c "$1"
  while IFS= read -r line; do
    case "$line" in
    *'cannot set terminal process group'* | *'no job control in this shell'*) ;;
    *) out+="${out:+$'\n'}${line}" ;;
    esac
  done <<<"$OUTPUT"
  OUTPUT="$out"
}

# Whether the terminal tests can run here (tmux installed): they skip otherwise
# Whether sh is busybox's (Alpine), for the rare setups the tests leave out there (no code for
# them: docs/troubleshooting.md's Limits)
function sh_is_busybox() {
  [[ "$(sh --help 2>&1)" == *BusyBox* ]]
}

function tty_available() {
  [[ -x "${TEST_DIR}/sysbin/tmux" ]]
}

# A shell in a terminal, for what only a terminal shows (the title, zsh's first screen, bash's
# preexec on 4.4-5.2): a private tmux server (stopped once the test ends), its window 100x30, in
# the home folder. Fails when the first prompt doesn't show
# usage: tty_start zsh|bash|<command>
function tty_start() {
  local cmd='zsh --no-globalrcs -i'
  case "$1" in
  zsh) ;;
  bash) cmd='bash --rcfile ~/.bashrc -i' ;;
  *) cmd="$1" ;;
  esac
  # (TERM screen: tmux 3.5+'s default, tmux-256color, may be missing from macOS's terminfo)
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u start-server \; set -g default-terminal screen \; \
    new-session -d -x 100 -y 30 -c "${SANDBOX}/home" "$cmd"
  # (its first prompt: the clock starts line 2; capture-pane drops trailing spaces)
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail 'no prompt in the terminal'; fi
}

# Type a line in the terminal (tty_start)
function tty_type() {
  run tmux -S "$TMUX_SOCKET" send-keys -l "$1"
  run tmux -S "$TMUX_SOCKET" send-keys Enter
}

# Set OUTPUT to the terminal's screen, or with "title", to its window title
function tty_read() {
  if [[ "${1:-}" == title ]]; then
    run tmux -S "$TMUX_SOCKET" display-message -p '#{pane_title}'
  else
    run tmux -S "$TMUX_SOCKET" capture-pane -p
  fi
}

# Whether the terminal's screen matches an extended regular expression
function tty_has() {
  tty_read
  grep -qE -- "$1" <<<"$OUTPUT"
}

# Whether the terminal's window title is the given text
function tty_title_is() {
  tty_read title
  [[ "$OUTPUT" == "$1" ]]
}

# Whether a window of the terminal is gone: its shell exited, its exit hooks done
# usage: tty_window_gone <window index>
function tty_window_gone() {
  run tmux -S "$TMUX_SOCKET" list-windows -F '#{window_index}'
  ! grep -qx -- "$1" <<<"$OUTPUT"
}

# Write a file in the sandbox's home
# usage: home_file <path> <content>
function home_file() {
  mkdir -p -- "$(dirname -- "${SANDBOX}/home/${1}")"
  printf '%s\n' "$2" >"${SANDBOX}/home/${1}"
}

# Whether the machine has its own Homebrew where oh-my-818 looks before ~/.linuxbrew (GitHub's
# macOS and Ubuntu runners): the tests' fake one wouldn't be used
function system_brew() {
  [[ -x /opt/homebrew/bin/brew || -x /usr/local/bin/brew ||
    -x /home/linuxbrew/.linuxbrew/bin/brew ]]
}

# A fake tool on PATH, printing its arguments
# usage: fake_tool <name> [<script body>]
function fake_tool() {
  # Replaces what is there (e.g. the link to the tests' bash), never writes through it
  rm -f -- "${SANDBOX}/bin/${1}"
  printf '#!/bin/sh\n%s\n' "${2:-printf '%s\n' "$1 \$*"}" >"${SANDBOX}/bin/${1}"
  chmod +x "${SANDBOX}/bin/${1}"
}

# Wait until a command succeeds, at most a few seconds (for the shells' background jobs)
# usage: wait_for <command> [<args>...]
function wait_for() {
  local _
  for _ in {1..50}; do
    if "$@"; then return 0; fi
    sleep 0.1
  done
  return 1
}

### Assertions

function fail() {
  local line
  if [[ -n "$SHELL_I" ]]; then printf '  in %s:\n' "$SHELL_I" >&2; fi
  printf '  %s\n' "$@" '  output:' >&2
  while IFS= read -r line; do printf '    | %s\n' "$line" >&2; done <<<"$OUTPUT"
  return 1
}

function assert_status() {
  if [[ "$STATUS" != "$1" ]]; then fail "expected status $1, got ${STATUS}"; fi
}

function assert_output_contains() {
  if [[ "$OUTPUT" != *"$1"* ]]; then fail "expected output to contain: $1"; fi
}

function assert_output_not_contains() {
  if [[ "$OUTPUT" == *"$1"* ]]; then fail "expected output not to contain: $1"; fi
}

# usage: assert_output_matches <extended regex>
function assert_output_matches() {
  if ! [[ "$OUTPUT" =~ $1 ]]; then fail "expected output to match: $1"; fi
}

function assert_output_eq() {
  if [[ "$OUTPUT" != "$1" ]]; then fail "expected output: $1"; fi
}

# usage: assert_file_contains <path in home> <text>
function assert_file_contains() {
  if ! grep -qF -- "$2" "${SANDBOX}/home/${1}" 2>/dev/null; then
    fail "expected ~/${1} to contain: $2"
  fi
}

# usage: assert_count <path in home> <text> <count>
function assert_count() {
  local n
  n="$(grep -cF -- "$2" "${SANDBOX}/home/${1}" || true)"
  if [[ "$n" != "$3" ]]; then fail "expected ${3} line(s) of '${2}' in ~/${1}, got ${n}"; fi
}
