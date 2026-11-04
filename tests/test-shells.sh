#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088 # shell code in single quotes, and outputs show ~
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of the zsh and bash modules (most of their code is shared: modules/shell/): startup,
# features, the user's files, integrations, the environment in interactive shells. Each test runs
# in both shells, unless it is about one of them. The prompt: test-prompt.sh.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

STATE='.local/state/om818'

function test_features() {
  local shell
  install
  for shell in zsh bash; do
    # History in the state folder, private, as many commands in memory as in the file
    shell_i "$shell" 'printf "%s\n" "$HISTFILE" "$HISTSIZE ${SAVEHIST:-$HISTFILESIZE}"
      typeset -f clipcopy _om818_title_precmd >/dev/null && printf "%s\n" functions'
    assert_output_eq "${SANDBOX}/home/.local/state/${shell}/history
20000 20000
functions"
    if [[ "$(ls -l -- "${SANDBOX}/home/.local/state/${shell}/history")" != -rw-------* ]]; then
      fail 'history not private'
    fi
  done
  # zsh: completion (compinit, zsh-completions), comments at the prompt as in bash, globs still
  # case-sensitive (the completion style turns that off)
  zsh_i 'whence -w compinit; [[ -n ${fpath[(r)*/zsh-completions/src]} ]] && print -r -- completions
    [[ -o interactive_comments ]] && print -r -- comments
    [[ -o case_glob ]] && print -r -- case_glob'
  assert_output_eq 'compinit: function
completions
comments
case_glob'
  # bash: generated completions next to the user's
  bash_i 'printf "%s\n" "$BASH_COMPLETION_USER_DIR"'
  assert_output_eq \
    "${SANDBOX}/home/.cache/om818/bash-completion:${SANDBOX}/home/.local/share/bash-completion"
}

function test_features_can_be_turned_off() {
  local shell
  home_file .config/om818/config.sh 'om818_history=off
om818_clipboard=off
om818_theme=off
om818_zsh_completions=off'
  install
  for shell in zsh bash; do
    # (each function on its own: typeset -f fails when any is missing)
    shell_i "$shell" 'printf "%s\n" "h=${HISTFILE:-}"
      for f in clipcopy prompt_om818-classic_precmd; do
        if typeset -f "$f" >/dev/null; then printf "%s\n" "$f"; fi
      done'
    # (zsh: no history file; bash: its own)
    if [[ "$shell" == zsh ]]; then
      assert_output_eq 'h='
    else
      assert_output_eq "h=${SANDBOX}/home/.bash_history"
    fi
  done
  zsh_i '[[ -n ${fpath[(r)*/zsh-completions/src]} ]] || print -r -- "no completions"'
  assert_output_eq 'no completions'
}

function test_bash_history() {
  home_file .config/om818/config.sh 'om818_history_share=on'
  install
  run bash -c 'for ((i = 0; i < 30000; i++)); do echo "$i"; done >~/.bash_history'
  # The commands in oh-my-818's file, the user's own file left (as each command runs, and
  # space-prefixed ones: see the terminal tests). Typed in an interactive bash reading stdin
  run bash -c 'printf "%s\n" "echo visible" "echo after" |
    bash --rcfile ~/.bashrc -i >/dev/null 2>&1
    cat ~/.local/state/bash/history'
  assert_output_eq 'echo visible
echo after'
  # The user's own history file keeps its length (bash truncates HISTFILE when HISTFILESIZE is set)
  run bash -c 'mapfile -t lines <~/.bash_history; echo "${#lines[@]}"'
  assert_output_eq 30000
  # Sharing is zsh's (bash can't do it exactly)
  zsh_i '[[ -o share_history ]] && print -r -- shared'
  assert_output_eq 'shared'
}

function test_shell_d() {
  local shell
  home_file .config/om818/shell.d/20-alias.sh "alias hi='printf \"%s\\\\n\" hi'"
  home_file .config/om818/shell.d/10-first.sh 'order=first'
  home_file .config/om818/shell.d/30-zsh.zsh 'order="$order zsh"'
  home_file .config/om818/shell.d/30-bash.bash 'order="$order bash"'
  home_file .config/om818/shell.d/notes.txt 'order=ignored'
  install
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" "$order"; hi'
    assert_output_eq "first ${shell}
hi"
  done
}

function test_integrations() {
  local shell
  # Fake tools whose init script records the arguments it was made with
  fake_tool direnv 'printf "%s\n" "direnv_args=\"$*\""'
  fake_tool fzf 'printf "%s\n" "fzf_args=\"$*\""'
  install
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" "direnv=${direnv_args:-} fzf=${fzf_args:-}"'
    assert_output_eq "direnv=hook ${shell} fzf="
  done
  # fzf replaces Ctrl+R: only when turned on. direnv turned off in bash only: the config is read
  # by each shell (the environment is generated from zsh's reading)
  home_file .config/om818/config.sh 'om818_fzf=on
if [ -n "${BASH_VERSION:-}" ]; then om818_direnv=off; fi'
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" "direnv=${direnv_args:-} fzf=${fzf_args:-}"'
    if [[ "$shell" == 'zsh' ]]; then
      assert_output_eq 'direnv=hook zsh fzf=--zsh'
    else
      assert_output_eq 'direnv= fzf=--bash'
    fi
  done
}

function test_tool_init_is_cached() {
  local shell
  # direnv's init script, recording each run of direnv
  fake_tool direnv 'printf x >>"$HOME/runs"; printf "%s\n" "direnv_ready=1"'
  install
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" "$direnv_ready"'
    assert_output_eq '1'
    shell_i "$shell" ':'
  done
  # Once per shell, then from the cache
  if [[ "$(<"${SANDBOX}/home/runs")" != 'xx' ]]; then fail 'not cached'; fi
  # Upgraded: a package's binary keeps its build time, older than the cache
  touch -t 200001010000 -- "${SANDBOX}/bin/direnv"
  for shell in zsh bash; do shell_i "$shell" ':'; done
  if [[ "$(<"${SANDBOX}/home/runs")" != 'xxxx' ]]; then fail 'not made again'; fi
  # Nix: a link into a store whose files all have the same time; upgraded, another store path
  store_tool direnv a
  for shell in zsh bash; do shell_i "$shell" ':'; done
  store_tool direnv b
  for shell in zsh bash; do shell_i "$shell" ':'; done
  if [[ "$(<"${SANDBOX}/home/runs")" != 'xxxxxxxx' ]]; then fail 'not made again (Nix)'; fi
}

# Move a fake tool into a store folder, Nix-like (a link to it, the time all store files have)
# usage: store_tool <name> <store folder name>
function store_tool() {
  local store="${SANDBOX}/store/${2}"
  mkdir -p -- "$store"
  if [[ -L "${SANDBOX}/bin/${1}" ]]; then
    cp -- "$(readlink -- "${SANDBOX}/bin/${1}")" "${store}/${1}"
  else
    cp -- "${SANDBOX}/bin/${1}" "${store}/${1}"
  fi
  touch -t 197001020000 -- "${store}/${1}"
  ln -sf -- "${store}/${1}" "${SANDBOX}/bin/${1}"
}

function test_failing_tool_init_is_quiet() {
  # An fzf too old for --zsh: its error is kept for `om818 status`, not printed (nor fzf run
  # again) at each start
  fake_tool fzf 'if [ "$1" = --zsh ]; then printf x >>"$HOME/runs"; fi
printf "%s\n" "unknown option: --zsh" >&2; exit 2'
  home_file .config/om818/config.sh 'om818_fzf=on'
  install
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
  if [[ "$(<"${SANDBOX}/home/runs")" != 'x' ]]; then fail 'run again'; fi
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains '! fzf: its setup command failed in zsh: unknown option: --zsh'
}

function test_generated_completions() {
  local shell
  # A tool shipping no completion, but printing one. (Not a system Homebrew's tools: each would
  # be waited for)
  # (run with OP_CACHE=false: else 1Password's op starts a daemon, which stays)
  # (nor leaving a config folder: 1Password's op makes ~/.config/op)
  fake_tool deno 'printf "%s\n" "${OP_CACHE:-unset}" >>"$HOME/runtime"
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/deno"
printf "%s\n" "#compdef deno" "complete -F _deno deno"'
  home_file .config/om818/config.sh 'om818_homebrew=off'
  install
  for shell in zsh bash; do shell_i "$shell" ':'; done
  # Made in the background, for the next shells
  if ! wait_for test -s "${SANDBOX}/home/.cache/om818/completions/_deno" ||
    ! wait_for test -s "${SANDBOX}/home/.cache/om818/bash-completion/completions/deno"; then
    fail 'no completion generated'
  fi
  if grep -v '^false$' "${SANDBOX}/home/runtime"; then fail 'run without OP_CACHE=false'; fi
  if [[ -e "${SANDBOX}/home/.config/deno" ]]; then fail 'a config folder left'; fi
  if [[ -n "$(find "${SANDBOX}/home/.cache/om818" -name '*.config.*')" ]]; then
    fail 'its throwaway config left'
  fi
  # Nix: upgraded to another store path, the same time
  store_tool deno a
  for shell in zsh bash; do shell_i "$shell" ':'; done
  wait_for test -s "${SANDBOX}/home/.cache/om818/bash-completion/completions-bin/deno"
  # (-e: macOS's sed takes a -- after the script for a file name)
  sed -e 's/_deno/_deno2/' -- "${SANDBOX}/store/a/deno" >"${SANDBOX}/deno.new"
  store_tool deno b
  cp -- "${SANDBOX}/deno.new" "${SANDBOX}/store/b/deno"
  touch -t 197001020000 -- "${SANDBOX}/store/b/deno"
  for shell in zsh bash; do shell_i "$shell" ':'; done
  if ! wait_for grep -q _deno2 "${SANDBOX}/home/.cache/om818/completions/_deno" ||
    ! wait_for grep -q _deno2 "${SANDBOX}/home/.cache/om818/bash-completion/completions/deno"; then
    fail 'not made again (Nix)'
  fi
}

function test_path_first() {
  local shell
  # A mise whose activation puts its tools first, and records the PATH it was activated with
  fake_tool mise 'printf "%s\n" "seen_path=\"\$PATH\"; PATH=\"/mise/tools:\$PATH\""'
  home_file .config/om818/env.d/10-guards.sh 'om818_path_first /guards'
  install
  for shell in zsh bash; do
    # First, in front of mise's tools (mise never sees it: it would keep it behind)
    shell_i "$shell" 'printf "%s\n" "${PATH%%:/mise/tools:*}"
      if [[ "$seen_path" == */guards* ]]; then printf "%s\n" "mise saw it"; fi'
    assert_output_eq '/guards'
    # Put back first before the prompt when something went in front (direnv, a virtualenv)
    shell_i "$shell" 'PATH="/venv/bin:$PATH"; _om818_path_first_keep; printf "%s\n" "${PATH%%:*}"'
    assert_output_eq '/guards'
  done
}

function test_path_front_restored() {
  local shell
  # As after macOS's path_helper: the system's folders moved in front of the environment's
  mkdir -p -- "${SANDBOX}/home/.local/bin"
  install
  for shell in zsh bash; do
    shell_i "$shell" 'PATH="/usr/bin:/bin:${PATH}"; _om818_path_front; printf "%s\n" "${PATH%%:*}"'
    assert_output_eq "${SANDBOX}/home/.local/bin"
  done
}

function test_starship_replaces_the_theme() {
  local shell
  fake_tool starship 'printf "%s\n" "starship_args=\"$*\""'
  home_file .config/om818/config.sh 'om818_starship=on'
  install
  for shell in zsh bash; do
    shell_i "$shell" 'printf "%s\n" "$starship_args"
      typeset -f prompt_om818-classic_precmd >/dev/null || printf "%s\n" "no theme"'
    assert_output_eq "init ${shell} --print-full-init
no theme"
  done
}

function test_clipboard_and_title() {
  local shell
  # A Wayland clipboard tool that keeps what it gets
  fake_tool wl-copy 'cat >"$HOME/copied"'
  fake_tool wl-paste 'cat "$HOME/copied"'
  install
  for shell in zsh bash; do
    shell_i "$shell" WAYLAND_DISPLAY=wayland-0 'printf "%s\n" hello | clipcopy; clippaste
      cd ~; t="$(_om818_title_precmd)"; [[ "$t" == $'"'"'\e]2;~\a'"'"' ]] && printf "%s\n" title'
    assert_output_eq 'hello
title'
    # Without a clipboard tool: a message, not "command not found"
    shell_i "$shell" 'clipcopy </dev/null'
    assert_output_contains 'clipcopy: no clipboard tool'
  done
}

function test_environment_stays_fresh() {
  local shell
  home_file .config/om818/config.sh 'om818_xdg=off'
  install
  # Not generated again at each start (it would cost every shell)
  printf '# untouched\n' >>"${SANDBOX}/home/${STATE}/env.sh"
  zsh_i 'print -r -- "cargo=${CARGO_HOME:-}"'
  assert_output_eq 'cargo='
  assert_file_contains "${STATE}/env.sh" '# untouched'
  # Generated again once the config changed (older than it, newer than the installed version)
  home_file .config/om818/config.sh '# all defaults'
  touch -t 200001010000 -- "${SANDBOX}/home/${STATE}/env.sh"
  touch -t 199901010000 -- "${SANDBOX}/home/.local/share/om818/.git/HEAD"
  zsh_i 'print -r -- "cargo=${CARGO_HOME:-}"'
  assert_output_eq "cargo=${SANDBOX}/home/.local/share/cargo"
}

function test_reload() {
  local shell rc
  home_file .config/om818/env.d/10-x.sh 'export X_VALUE=one'
  install
  # Sourcing the rc file again: env.d/ read again, no hook added twice
  for shell in zsh bash; do
    rc='~/.bashrc'
    if [[ "$shell" == 'zsh' ]]; then rc='"$ZDOTDIR/.zshrc"'; fi
    shell_i "$shell" 'n="${#precmd_functions[@]} ${#preexec_functions[@]}"
      printf "%s\n" "export X_VALUE=two" >|~/.config/om818/env.d/10-x.sh
      source '"$rc"'
      printf "%s\n" "$X_VALUE ${#precmd_functions[@]} ${#preexec_functions[@]} / $n"'
    if [[ ! "$OUTPUT" =~ ^two\ ([0-9]+\ [0-9]+)\ /\ ([0-9]+\ [0-9]+)$ ]]; then
      fail 'unexpected output'
    elif [[ "${BASH_REMATCH[1]}" != "${BASH_REMATCH[2]}" ]]; then
      fail 'hooks added twice'
    fi
  done
}

function test_says_when_zshrc_changes() {
  # ~/.zshrc, no longer read: the installer says it last (where it can't scroll by)
  home_file .zshrc "alias k=kubectl"
  install
  if [[ "${OUTPUT##*$'\n\n'}" != 'zsh users: zsh now reads ~/.config/zsh/, not ~/.zshrc.'* ]]; then
    fail 'the warning is not last'
  fi
  # Its output not seen (no terminal: cloud-init, Ansible, a dotfiles tool): the first zsh says
  # it too, once, and a repair no longer does
  zsh_i 'print -r -- ready'
  assert_output_contains 'oh-my-818: zsh no longer reads ~/.zshrc: it reads ~/.config/zsh/ instead'
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" install
  assert_output_not_contains 'zsh users:'
  # A tool's installer appends to it: said once
  touch -t 200001010000 -- "${SANDBOX}/home/${STATE}/zsh-files-seen"
  home_file .zshrc 'export PATH="$HOME/.tool/bin:$PATH"'
  zsh_i 'print -r -- ready'
  assert_output_contains 'oh-my-818: ~/.zshrc changed (a tool'"'"'s installer?), but zsh reads'
  zsh_i 'print -r -- ready'
  assert_output_eq 'ready'
}

# At a terminal (the SSH line), the installer's notice is enough: the first zsh doesn't repeat it
function test_zsh_notice_once_at_a_terminal() {
  tty_available || return 0
  home_file .zshrc 'alias k=kubectl'
  tty_start "sh ${FIXTURE}/install.sh; exec zsh --no-globalrcs -i"
  if ! tty_has 'zsh users: zsh now reads'; then fail "no notice: ${OUTPUT}"; fi
  if tty_has 'zsh no longer reads'; then fail "said again: ${OUTPUT}"; fi
}

function test_zsh_completion_dump_follows_the_version() {
  install
  # A dump older than the installed version (an update may bring completions): made again
  mkdir -p -- "${SANDBOX}/home/.cache/om818"
  printf '# old dump\n' >"${SANDBOX}/home/.cache/om818/zcompdump"
  touch -t 200001010000 -- "${SANDBOX}/home/.cache/om818/zcompdump"
  zsh_i ':'
  if [[ -e "${SANDBOX}/home/.cache/om818/zcompdump" ]]; then fail 'the old dump is kept'; fi
}

function test_config_typos_said_once() {
  install
  # A shell regenerating the environment after config.sh changed checks it, once
  home_file .config/om818/config.sh 'om818_prompt_date_tx=UTC
om818_fzf=yes'
  zsh_i 'print -r -- ready'
  assert_output_contains \
    'oh-my-818: ~/.config/om818/config.sh: unknown settings: om818_prompt_date_tx;'
  assert_output_contains 'invalid values: om818_fzf=yes (auto, on or off)'
  bash_i 'printf "%s\n" ready'
  assert_output_eq 'ready'
}

function test_terminal_bash() {
  tty_available || return 0
  bash_terminal
}

# Where touch -r keeps whole seconds (old busybox): a tool upgraded to a binary older than its
# cached script (e.g. a package built before) is still seen
function test_cache_with_coarse_times() {
  local touch
  touch="$(command -v touch)"
  fake_tool touch 'if [ "$1" = -r ]; then
  exec '"$touch"' -t "$(date -r "$2" +%Y%m%d%H%M.%S)" -- "$4"
fi
exec '"$touch"' "$@"'
  fake_tool direnv 'echo "echo direnv-v1"'
  home_file .config/om818/config.sh 'om818_direnv=on'
  install
  zsh_i 'true'
  assert_output_contains 'direnv-v1'
  if ! compgen -G "${SANDBOX}/home/.cache/om818/eval/*.coarse" >/dev/null; then
    fail 'no coarse mark: touch -r kept the exact time'
  fi
  fake_tool direnv 'echo "echo direnv-v2"'
  "$touch" -t 202001010000 -- "${SANDBOX}/bin/direnv"
  zsh_i 'true'
  assert_output_contains 'direnv-v2'
}

# Where touch -r keeps whole seconds: the cached script is still used, not made again at each start
function test_coarse_cache_is_used() {
  local touch
  touch="$(command -v touch)"
  fake_tool touch 'if [ "$1" = -r ]; then
  exec '"$touch"' -t "$(date -r "$2" +%Y%m%d%H%M.%S)" -- "$4"
fi
exec '"$touch"' "$@"'
  fake_tool direnv 'printf x >>"$HOME/runs"; echo "echo direnv-v1"'
  home_file .config/om818/config.sh 'om818_direnv=on'
  install
  rm -f -- "${SANDBOX}/home/runs"
  zsh_i 'true'
  zsh_i 'true'
  if [[ "$(<"${SANDBOX}/home/runs")" != x ]]; then fail "direnv ran $(<"${SANDBOX}/home/runs")"; fi
}

# bash-preexec before 0.7 (distributions' packages) loaded by the user first: PROMPT_COMMAND stays
# a string (all it handles), the title's line before its install lines (here only its entry, and
# the variable that keeps the vendored one from loading)
function test_bash_title_with_an_old_preexec() {
  home_file .bashrc 'bash_preexec_imported=defined
PROMPT_COMMAND=$'"'"'sys\n__bp_trap_string="$(trap -p DEBUG)"\ntrap - DEBUG\n__bp_install'"'"
  install
  # (not declare -p's quoting, which differs between bash versions)
  bash_i 'if [[ "$(declare -p PROMPT_COMMAND)" == "declare -- "* ]]; then echo string; fi
    printf "%s\n" "$PROMPT_COMMAND"'
  assert_output_contains $'string\nsys\n_om818_title_precmd\n__bp_trap_string='
}

# direnv's environment in the prompt at once, in bash too (its hook goes in PROMPT_COMMAND)
function test_terminal_bash_direnv() {
  tty_available || return 0
  fake_tool direnv 'case "$1" in
hook) cat <<"EOF"
_direnv_hook() {
  local status=$?
  eval "$(direnv export bash)"
  return $status
}
if [[ ";${PROMPT_COMMAND[*]:-};" != *";_direnv_hook;"* ]]; then
  if [[ "$(declare -p PROMPT_COMMAND 2>&1)" == "declare -a"* ]]; then
    PROMPT_COMMAND=(_direnv_hook "${PROMPT_COMMAND[@]}")
  else
    PROMPT_COMMAND="_direnv_hook${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  fi
fi
EOF
;;
export)
  printf x >>"$HOME/runs"
  case "$PWD" in */envd) echo "export VIRTUAL_ENV=$PWD/.venv" ;; *) echo "unset VIRTUAL_ENV" ;; esac
  ;;
esac'
  mkdir -p -- "${SANDBOX}/home/envd"
  install
  # The user's own hook too, after the om818 line: still once per prompt
  printf '%s\n' 'eval "$(direnv hook bash)"' >>"${SANDBOX}/home/.bashrc"
  tty_start bash
  tty_type 'cd envd'
  if ! wait_for tty_has '\(venv:envd\)'; then fail "no venv: $(tty_read && echo "$OUTPUT")"; fi
  rm -f -- "${SANDBOX}/home/runs"
  tty_type 'true'
  sleep 1
  if [[ "$(<"${SANDBOX}/home/runs")" != x ]]; then fail "direnv ran $(<"${SANDBOX}/home/runs")"; fi
}

# om818_history=off: the user's own HISTCONTROL, set in shell.d/ (after bash-preexec is loaded),
# still keeps space-prefixed commands out
function test_terminal_bash_own_histcontrol() {
  tty_available || return 0
  home_file .config/om818/config.sh 'om818_history=off'
  home_file .config/om818/shell.d/history.bash 'HISTCONTROL=ignoreboth'
  install
  tty_start bash
  tty_type ' true # secret'
  tty_type 'echo keep'
  tty_type 'exit'
  if ! wait_for grep -qs keep "${SANDBOX}/home/.bash_history"; then fail 'history not written'; fi
  if grep -q secret "${SANDBOX}/home/.bash_history"; then fail 'a space-prefixed command saved'; fi
}

# The same with bash-preexec loaded by the user's ~/.bashrc before oh-my-818 (atuin's setup), and
# running preexec from a DEBUG trap, as on bash 4.4-5.2 (here forced; test_terminal_bash takes
# that path there too)
function test_terminal_bash_preexec_loaded_first() {
  tty_available || return 0
  bash_terminal debug early
}

# usage: bash_terminal [debug [early]]
function bash_terminal() {
  local preexec="${SANDBOX}/home/.local/share/om818/vendor/bash-preexec/bash-preexec.sh"
  # A system PROMPT_COMMAND setting the title (Fedora's /etc/bashrc, VTE), before oh-my-818's line
  printf '%s\n' 'PROMPT_COMMAND='"'"'printf "\033]0;system\007"'"'" >"${SANDBOX}/home/.bashrc"
  # early: bash-preexec loaded by the user before oh-my-818 (atuin's setup)
  if [[ "${2:-}" == early ]]; then
    printf '%s\n' 'source ~/.local/share/om818/vendor/bash-preexec/bash-preexec.sh' \
      >>"${SANDBOX}/home/.bashrc"
  fi
  # (a command of 2 s shows its duration: no longer waits)
  home_file .config/om818/config.sh 'om818_prompt_duration_min=1'
  install
  if [[ "${1:-}" == debug ]]; then
    sed -i.orig 's/^\(    __bp_hook_preexec_proc=__bp_hook_preexec_into_\)ps0$/\1debug/' \
      "$preexec"
    if cmp -s -- "$preexec" "${preexec}.orig"; then fail "bash-preexec's DEBUG path not forced"; fi
  fi
  tty_start bash
  # The first command gets its preexec: kept out of the history when it starts with a space (an
  # entry of PROMPT_COMMAND after bash-preexec's would take its turn on the DEBUG path)
  tty_type ' true # secret-first'
  # The title of a command, and its duration (bash 5+: EPOCHREALTIME)
  tty_type 'sleep 2'
  if ! wait_for tty_title_is 'sleep 2'; then fail "title: $(tty_read title && echo "$OUTPUT")"; fi
  # The folder's title once it ended, after the system's
  if ! wait_for tty_title_is '~'; then fail "title: $(tty_read title && echo "$OUTPUT")"; fi
  if ((BASH_VERSINFO[0] >= 5)) && ! tty_has '✔ 2s '; then fail 'no duration'; fi
  # In the history as it ran, not when the shell exits (new terminals see it)
  if ! wait_for grep -qx 'sleep 2' "${SANDBOX}/home/.local/state/bash/history"; then
    fail 'not written as it ran'
  fi
  # A command starting with a space: not in the title, nor in the history, even when the shell
  # ends while it runs (the entry goes as it starts)
  tty_type ' sleep 1 # secret-title'
  sleep 0.5
  tty_read title
  assert_output_eq '~'
  sleep 0.6
  # (exec runs commands, not builtins such as true)
  tty_type ' exec sleep 0 # secret-exec'
  if ! wait_for tty_window_gone 0; then fail 'the shell still runs'; fi
  assert_file_contains .local/state/bash/history 'sleep 2'
  if grep -q secret "${SANDBOX}/home/.local/state/bash/history"; then
    fail "a space-prefixed command saved: $(grep secret -- \
      "${SANDBOX}/home/.local/state/bash/history")"
  fi
}

function test_zsh_option_arrows() {
  install
  # Option+right in both keymaps: emacs, and vi for its users (bindkey -v in shell.d/)
  home_file .config/om818/shell.d/vi.zsh 'bindkey -v'
  zsh_i 'bindkey -M emacs "^[[1;3C"; bindkey "^[[1;3C"; bindkey -M vicmd "^[[1;3C"'
  assert_output_eq $'"^[[1;3C" forward-word\n"^[[1;3C" forward-word\n"^[[1;3C" forward-word'
}

function test_terminal_zsh_first_screen() {
  # Lines printed before the first prompt stay on the screen (zsh-defer's redraw erased them)
  install
  home_file .config/om818/config.sh 'om818_prompt_dat_tz=UTC'
  # Two async answers (gitstatus) redrawing at once: the line above the prompt stays too
  home_file .config/om818/shell.d/redraw.zsh 'function _test_redraw() {
  _om818_prompt_redraw
  _om818_prompt_redraw
}
zle -N _test_redraw
bindkey "^G" _test_redraw'
  tty_available || return 0
  tty_start zsh
  tty_read
  assert_output_contains 'unknown settings: om818_prompt_dat_tz'
  tty_type 'print -r -- "a${HOME:+b}c"'
  run tmux -S "$TMUX_SOCKET" send-keys C-g
  sleep 1
  tty_read
  assert_output_contains $'\nabc\n'
}

# A reload (source ~/.bashrc) leaves bash-preexec's HISTCONTROL as it was: else the next command
# starting with a space gets the one before as its title
function test_terminal_bash_reload() {
  tty_available || return 0
  install
  tty_start bash
  tty_type 'source ~/.bashrc'
  tty_type 'echo one'
  tty_type ' sleep 3 # secret'
  sleep 1
  tty_read title
  assert_output_eq '~'
}

# A tool's hook removed from PROMPT_COMMAND as a whole entry only (not my_tool_hook_log)
function test_prompt_command_entry_removal() {
  install
  bash_i 'unset PROMPT_COMMAND; PROMPT_COMMAND=$'"'"'a_hook_x;_hook\n_hook;b\n_hook_log'"'"'
    _om818_prompt_command_remove _hook; printf "%s|" "${PROMPT_COMMAND[@]}"'
  assert_output_eq $'a_hook_x\nb\n_hook_log|'
  # (with blanks around ;)
  bash_i 'unset PROMPT_COMMAND; PROMPT_COMMAND="history -a; _hook ; true; _hook"
    _om818_prompt_command_remove _hook; printf "%s|" "$PROMPT_COMMAND"'
  assert_output_eq 'history -a; true|'
  bash_i 'unset PROMPT_COMMAND; PROMPT_COMMAND="_hook ; a; _hook;b"
    _om818_prompt_command_remove _hook; printf "%s|" "$PROMPT_COMMAND"'
  assert_output_eq ' a;b|'
}

# bash-preexec before 0.7 loaded first, with an array PROMPT_COMMAND (Fedora 42+'s profile adds an
# item after its lines): joined back into the string it handles, its install lines last, the title
# line before them
function test_bash_old_preexec_install_lines_last() {
  local bp=$'__bp_trap_string="$(trap -p DEBUG)"\ntrap - DEBUG\n__bp_install'
  # shellcheck disable=SC2016 # written as is
  home_file .bashrc 'bash_preexec_imported=defined
bp=$'"'"'__bp_trap_string="$(trap -p DEBUG)"\ntrap - DEBUG\n__bp_install'"'"'
PROMPT_COMMAND=($'"'"'sys\n'"'"'"$bp" other)'
  install
  bash_i 'if [[ "$(declare -p PROMPT_COMMAND)" == "declare -- "* ]]; then echo string; fi
    printf "%s\n" "$PROMPT_COMMAND"'
  assert_output_contains $'string\nsys\n_om818_title_precmd\nother\n'"$bp"
}

# A read-only PROMPT_COMMAND (servers logging commands): no prompt nor title then, but quietly
function test_bash_read_only_prompt_command() {
  home_file .bashrc "readonly PROMPT_COMMAND='true'"
  # (the tools' hooks setting PROMPT_COMMAND, as mise's, direnv's, zoxide's: not run then)
  fake_tool mise 'echo "PROMPT_COMMAND=x"'
  fake_tool direnv 'echo "PROMPT_COMMAND=x"'
  fake_tool zoxide 'echo "PROMPT_COMMAND=x"'
  home_file .config/om818/config.sh 'om818_zoxide=on'
  install
  bash_i 'echo "ready $om818_title $om818_theme $om818_update"'
  assert_output_eq 'ready off off off'
}

# OM818_LOCKED and OM818_PROBE (set for om818's commands) don't reach the shells' children
function test_shells_drop_om818_variables() {
  local shell
  install
  for shell in zsh bash; do
    shell_i "$shell" OM818_LOCKED=1 OM818_PROBE=1 \
      'env | grep -E "^OM818_(LOCKED|PROBE)=" || echo none'
    assert_output_eq 'none'
  done
}

run_tests "$@"
