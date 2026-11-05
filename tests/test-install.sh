#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088 # shell code in single quotes, and status shows ~
set -Eeuo pipefail
shopt -s inherit_errexit

# Tests of install.sh and `om818 install`: cloning, the release checked out, startup files.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

function test_installs_the_latest_release() {
  add_release v0.2.0
  install
  assert_output_contains 'oh-my-818 v0.2.0 is installed'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" version
  assert_output_eq 'v0.2.0'
}

function test_wires_the_startup_files() {
  install
  assert_file_contains .zshenv 'export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"; fi # om818'
  assert_file_contains .zshenv '/om818/env.sh"; fi # om818'
  assert_file_contains .config/zsh/.zshrc '/om818/om818.plugin.zsh"; fi # om818'
  assert_file_contains .profile '/om818/env.sh"; fi # om818'
  if [[ ! -s "${SANDBOX}/home/.local/state/om818/env.sh" ]]; then fail 'no env.sh'; fi
  # The folders for the user's files, there to be found
  if [[ ! -d "${SANDBOX}/home/.config/om818/env.d" ||
    ! -d "${SANDBOX}/home/.config/om818/shell.d" ]]; then
    fail 'no env.d or shell.d'
  fi
  # ~/.bashrc for bash 4.4+ (on PATH: the tests' bash), not the login files bash reads instead of
  # ~/.profile
  assert_file_contains .bashrc '/om818/om818.plugin.bash"; fi # om818'
  if [[ -e "${SANDBOX}/home/.bash_profile" || -e "${SANDBOX}/home/.bash_login" ]]; then
    fail 'created a bash login file'
  fi
  # Run again (the install line repairs): nothing added
  install
  assert_output_contains 'already in'
  assert_count .zshenv '# om818' 2
  assert_count .config/zsh/.zshrc '# om818' 1
  assert_count .profile '# om818' 1
  assert_count .bashrc '# om818' 2
}

function test_wires_existing_bash_files() {
  home_file .bashrc '# mine'
  home_file .bash_profile '# mine'
  install
  assert_file_contains .bashrc '# mine'
  assert_file_contains .bashrc '/om818/om818.plugin.bash"; fi # om818'
  # The environment first: Debian's and Ubuntu's .bashrc return early when not interactive
  if [[ "$(head -n 1 -- "${SANDBOX}/home/.bashrc")" != *'/om818/env.sh"; fi # om818' ]]; then
    fail 'the environment line is not first in ~/.bashrc'
  fi
  assert_file_contains .bash_profile '/om818/env.sh"; fi # om818'
}

function test_leaves_a_dotfiles_layout_alone() {
  # Read-only entry points loading oh-my-818 through other files, and another ZDOTDIR
  home_file .zshenv 'export ZDOTDIR="$HOME/.zsh"
. ~/.local/state/om818/env.sh'
  home_file .zsh/.zshrc 'source ~/.local/share/om818/om818.plugin.zsh'
  home_file .config/bash/bashrc 'source ~/.local/share/om818/om818.plugin.bash'
  home_file .bashrc 'source ~/.config/bash/bashrc'
  home_file .profile '. ~/.local/state/om818/env.sh'
  home_file .zshrc '# guard'
  chmod a-w "${SANDBOX}/home/.zshenv" "${SANDBOX}/home/.zsh/.zshrc" "${SANDBOX}/home/.bashrc" \
    "${SANDBOX}/home/.profile" "${SANDBOX}/home/.zshrc"
  install
  assert_output_not_contains 'warning'
  assert_output_not_contains 'updated'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains '~/.zsh/.zshrc: ok (loads oh-my-818 in zsh, read-only)'
  assert_output_contains '~/.bashrc: ok (loads the environment and oh-my-818 in bash, read-only)'
}

function test_never_writes_a_read_only_file() {
  home_file .bashrc '# protected'
  chmod a-w "${SANDBOX}/home/.bashrc"
  install
  assert_output_contains 'warning: '
  assert_output_contains '/.bashrc is read-only: add this line yourself'
  assert_output_not_contains 'Permission denied'
}

function test_login_bash_reads_bashrc() {
  # bash as the login shell, no login file sourcing ~/.bashrc (macOS)
  install SHELL=/bin/bash
  assert_file_contains .profile '. "$HOME/.bashrc"; fi # om818'
  # A login shell reading ~/.profile, without the system's /etc/profile (bash -l would run it:
  # the tests must not depend on the machine's startup files) nor ~/.bashrc by itself
  run SHELL=/bin/bash bash --norc -i -c '. ~/.profile; printf "%s\n" "$om818_shell"' </dev/null
  assert_output_contains 'bash'
}

function test_repair() {
  # A development install (a commit after the last release), repaired: back on that release
  printf 'x\n' >"${FIXTURE}/.unreleased"
  git_ -C "$FIXTURE" add .unreleased
  git_ -C "$FIXTURE" commit -qm unreleased
  install OM818_REF=main
  install
  assert_output_contains 'repairing'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" version
  assert_output_eq 'v0.1.0'
  # On a release, a repair keeps it: updating is `om818 update`'s job
  add_release v0.2.0
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" version
  assert_output_eq 'v0.1.0'
}

function test_reads_the_config_without_a_recent_bash() {
  # macOS: /bin/bash is 3.2, which can't read defaults.sh's tables
  fake_tool bash 'exit 1'
  home_file .config/om818/config.sh 'om818_xdg=off'
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains '~/.config/om818/config.sh: ok'
  if grep -q CARGO_HOME "${SANDBOX}/home/.local/state/om818/env.sh"; then fail 'config not read'; fi
}

function test_fails_without_a_release_unless_asked() {
  git_ -C "$FIXTURE" tag -d v0.1.0 >/dev/null
  run sh "${FIXTURE}/install.sh"
  assert_status 1
  assert_output_contains 'no release yet'
  # Nothing left behind (a new account: no ~/.local yet): running it again starts over
  if [[ -e "${SANDBOX}/home/.local" ]]; then fail 'a failed install left its clone'; fi
  install OM818_REF=main
  assert_output_contains 'is installed'
}

function test_refuses_a_folder_that_is_not_a_clone() {
  # Something else at the install's place: left as it is, not replaced (nor deleted on failure)
  home_file .local/share/om818/mine.txt 'mine'
  run sh "${FIXTURE}/install.sh"
  assert_status 1
  assert_output_contains 'is not a clone of oh-my-818: move it away first'
  assert_file_contains .local/share/om818/mine.txt 'mine'
}

function test_copies_the_old_history() {
  home_file .zsh_history ': 1700000000:0;echo old-zsh'
  home_file .bash_history 'echo old-bash'
  install
  assert_output_contains 'copied your zsh history (~/.zsh_history)'
  assert_file_contains .local/state/zsh/history 'echo old-zsh'
  assert_file_contains .local/state/bash/history 'echo old-bash'
  if [[ "$(ls -l -- "${SANDBOX}/home/.local/state/zsh/history")" != '-rw-------'* ]]; then
    fail 'the history is not private'
  fi
  # Once: oh-my-818's history is never replaced
  chmod 644 "${SANDBOX}/home/.local/state/bash/history"
  install
  assert_output_not_contains 'copied'
  # (and made private again, e.g. after a backup restored it readable by others)
  if [[ "$(ls -l -- "${SANDBOX}/home/.local/state/bash/history")" != -rw-------* ]]; then
    fail "not private again: $(ls -l -- "${SANDBOX}/home/.local/state/bash/history")"
  fi
}

function test_symlinked_home() {
  local real
  # As macOS's /var -> /private/var: HOME through a link, the install's path resolved or not
  ln -s -- home "${SANDBOX}/link"
  install HOME="${SANDBOX}/link"
  assert_file_contains .config/zsh/.zshrc \
    '"${XDG_DATA_HOME:-$HOME/.local/share}/om818/om818.plugin.zsh"'
  # (resolved: the sandbox's own path may go through a link, macOS's TMPDIR in /var)
  real="$(cd -P -- "${SANDBOX}/home" && pwd -P)"
  run HOME="${SANDBOX}/link" "${real}/.local/share/om818/bin/om818" status
  assert_output_contains 'oh-my-818 v0.1.0 (~/.local/share/om818)'
  assert_output_not_contains "$SANDBOX"
  assert_output_not_contains "$real"
}

function test_environment_for_non_interactive_bash() {
  # bash reads ~/.bashrc for `ssh host cmd` too: the one the installer creates loads the
  # environment, and the module stops at once
  install
  run bash -c '. ~/.bashrc; printf "%s\n" "${CARGO_HOME:-none}" "${om818_shell:-no module}"'
  assert_output_eq "${SANDBOX}/home/.local/share/cargo
no module"
  # Debian's and Ubuntu's .bashrc stop early when not interactive: the environment comes before
  rm -rf -- "${SANDBOX:?}/home"
  mkdir -- "${SANDBOX}/home"
  home_file .bashrc '# ~/.bashrc: executed by bash(1) for non-login shells.
case $- in
    *i*) ;;
      *) return;;
esac'
  install
  run bash -c '. ~/.bashrc; printf "%s\n" "${CARGO_HOME:-none}" "${om818_shell:-no module}"'
  assert_output_eq "${SANDBOX}/home/.local/share/cargo
no module"
}

# usage: assert_read_only <path in home>... (a missing file fails)
function assert_read_only() {
  local file
  for file in "$@"; do
    if [[ ! -e "${SANDBOX}/home/${file}" || -w "${SANDBOX}/home/${file}" ]]; then
      fail "~/${file} not read-only"
    fi
  done
}

function test_protects_startup_files() {
  home_file .bashrc '# mine'
  home_file .config/om818/config.sh 'om818_protect_startup_files=on'
  install
  assert_read_only .zshenv .config/zsh/.zshrc .profile .bashrc
  assert_output_contains 'made read-only (om818_protect_startup_files=on): ~/.zshenv,'
  assert_output_contains '~/.config/zsh/.zshrc, ~/.profile, ~/.bashrc, ~/.zshrc'
  # Empty guards: ~/.zshrc (zsh reads ~/.config/zsh/.zshrc), and the zsh files an installer
  # following ZDOTDIR could create
  local guard
  for guard in .zshrc .config/zsh/.zshenv .config/zsh/.zprofile .config/zsh/.zlogin; do
    assert_read_only "$guard"
    if [[ -s "${SANDBOX}/home/${guard}" ]]; then fail "~/${guard} not empty"; fi
  done
  # A repair (as after an update): still protected, nothing to say; a line missing from a file it
  # protected (e.g. one a new version adds) added
  chmod u+w "${SANDBOX}/home/.profile"
  printf '# emptied\n' >"${SANDBOX}/home/.profile"
  chmod a-w "${SANDBOX}/home/.profile"
  install
  assert_file_contains .profile '/om818/env.sh"; fi # om818'
  assert_output_not_contains 'read-only'
  assert_read_only .zshenv .config/zsh/.zshrc .profile .bashrc .zshrc
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains '~/.zshrc: empty read-only guard: ok'
  assert_output_not_contains 'writable'
}

function test_protection_turned_off() {
  # A file the user protected: theirs, left read-only
  home_file .bash_profile '. ~/.local/state/om818/env.sh'
  chmod a-w "${SANDBOX}/home/.bash_profile"
  home_file .config/om818/config.sh 'om818_protect_startup_files=on'
  install
  home_file .config/om818/config.sh 'om818_protect_startup_files=off'
  install
  assert_output_contains 'writable again (om818_protect_startup_files=off): ~/.zshenv'
  local file
  for file in .zshenv .config/zsh/.zshrc .profile .bashrc; do
    if [[ ! -w "${SANDBOX}/home/${file}" ]]; then fail "~/${file} still read-only"; fi
  done
  if [[ -e "${SANDBOX}/home/.zshrc" || -e "${SANDBOX}/home/.config/zsh/.zprofile" ]]; then
    fail 'a guard left'
  fi
  assert_read_only .bash_profile
}

function test_uninstall() {
  local file
  home_file .bashrc '# mine'
  home_file .zshrc '# mine'
  home_file .config/om818/config.sh 'om818_protect_startup_files=on'
  install
  # A history (none before: a new account), and a folder the xdg integration gave a tool
  mkdir -p -- "${SANDBOX}/home/.local/state/zsh"
  printf ': 2:0;pwd\n' >>"${SANDBOX}/home/.local/state/zsh/history"
  mkdir -p -- "${SANDBOX}/home/.local/share/cargo"
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0
  # The startup files as they were: oh-my-818's lines gone, files it created deleted, writable
  for file in .bashrc .zshrc; do
    if [[ "$(<"${SANDBOX}/home/${file}")" != '# mine' || ! -w "${SANDBOX}/home/${file}" ]]; then
      fail "~/${file} not as it was"
    fi
  done
  for file in .zshenv .profile .config/zsh; do
    if [[ -e "${SANDBOX}/home/${file}" ]]; then fail "~/${file} left"; fi
  done
  # The history back where the shell reads it
  if [[ "$(<"${SANDBOX}/home/.zsh_history")" != ': 2:0;pwd' ]]; then
    fail 'history not back'
  fi
  assert_output_contains 'without oh-my-818, cargo uses ~/.cargo: mv ~/.local/share/cargo ~/.cargo'
  # oh-my-818 gone, the user's files kept
  for file in .local/share/om818 .local/state/om818 .local/state/zsh .cache/om818; do
    if [[ -e "${SANDBOX}/home/${file}" ]]; then fail "~/${file} left"; fi
  done
  if [[ ! -e "${SANDBOX}/home/.config/om818/config.sh" ]]; then fail 'config.sh removed'; fi
}

# Coming from oh-my-zsh: ~/.zshrc set aside as status says, then uninstall: it is back (and
# oh-my-zsh with it), as the other files set aside, unless a new one was written since (e.g. by a
# tool's installer): that one stays, and the copy too
function test_uninstall_puts_back_a_zshrc_set_aside() {
  local file
  home_file .zshrc 'source $ZSH/oh-my-zsh.sh'
  home_file .zlogin 'old zlogin'
  home_file .zprofile 'old zprofile'
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains 'mv ~/.zshrc ~/.zshrc.pre-om818'
  for file in .zshrc .zlogin .zprofile; do
    mv -- "${SANDBOX}/home/${file}" "${SANDBOX}/home/${file}.pre-om818"
  done
  # (read-only, as om818_protect_startup_files leaves a file it protected)
  chmod 444 "${SANDBOX}/home/.zshrc.pre-om818"
  # Written again since (a tool's installer): status doesn't say to set it aside a second time,
  # which would replace the copy
  home_file .zprofile 'new zprofile'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains 'written since ~/.zprofile.pre-om818 was set aside'
  assert_output_not_contains 'mv ~/.zprofile ~/.zprofile.pre-om818'
  # (over SSH: log out, as a shell started from this one keeps oh-my-818's variables)
  run SSH_CONNECTION='1.2.3.4 5 6.7.8.9 22' "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_output_contains '~/.zshrc is back'
  assert_output_contains 'Log out and connect again'
  assert_output_not_contains 'exec'
  assert_output_contains '~/.zprofile.pre-om818 (your .zprofile before oh-my-818) is kept'
  if [[ "$(<"${SANDBOX}/home/.zshrc")" != 'source $ZSH/oh-my-zsh.sh' ]]; then
    fail '~/.zshrc not back'
  fi
  if [[ ! -w "${SANDBOX}/home/.zshrc" ]]; then fail '~/.zshrc back read-only'; fi
  if [[ -e "${SANDBOX}/home/.zshrc.pre-om818" ]]; then fail 'the copy left'; fi
  if [[ "$(<"${SANDBOX}/home/.zlogin")" != 'old zlogin' ]]; then fail '~/.zlogin not back'; fi
  if [[ "$(<"${SANDBOX}/home/.zprofile")" != 'new zprofile' ]]; then fail '~/.zprofile replaced'; fi
  if [[ ! -e "${SANDBOX}/home/.zprofile.pre-om818" ]]; then fail 'its copy removed'; fi
}

function test_uninstall_keeps_both_histories() {
  home_file .bash_history 'old'
  install
  # The terminal that ran the installer writes to the old file when it closes; the new one
  # gets commands meanwhile. Shells may have trimmed either: both stay
  printf 'closing\n' >>"${SANDBOX}/home/.bash_history"
  printf 'new\n' >>"${SANDBOX}/home/.local/state/bash/history"
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0
  assert_output_contains 'mv ~/.local/state/bash/history ~/.bash_history'
  if [[ "$(<"${SANDBOX}/home/.bash_history")" != $'old\nclosing' ||
  "$(<"${SANDBOX}/home/.local/state/bash/history")" != $'old\nnew' ]]; then
    fail 'a history file changed'
  fi
}

function test_uninstall_history_links_and_own_histfile() {
  home_file .bash_history 'ls'
  install
  # One file through a hard link: said so, left as it is
  rm -f -- "${SANDBOX}/home/.local/state/bash/history"
  ln -- "${SANDBOX}/home/.bash_history" "${SANDBOX}/home/.local/state/bash/history"
  # A dangling ~/.zsh_history link (into dotfiles not there yet): never replaced
  mkdir -p -- "${SANDBOX}/home/.local/state/zsh"
  printf 'new\n' >>"${SANDBOX}/home/.local/state/zsh/history"
  ln -s -- dotfiles/zsh_history "${SANDBOX}/home/.zsh_history"
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0
  assert_output_contains 'are one file: left as it is'
  if [[ ! -L "${SANDBOX}/home/.zsh_history" ]]; then fail 'the link replaced'; fi
  assert_output_contains 'mv ~/.local/state/zsh/history ~/.zsh_history'
}

function test_uninstall_keeps_a_history_the_user_points_to() {
  local file
  # The user's own HISTFILE at oh-my-818's path (the Arch wiki's), in ~/.bashrc or a login file:
  # the file stays where it is
  for file in .bashrc .profile; do
    rm -rf -- "${SANDBOX:?}/home"
    mkdir -- "${SANDBOX}/home"
    install
    mkdir -p -- "${SANDBOX}/home/.local/state/bash"
    printf 'mine\n' >"${SANDBOX}/home/.local/state/bash/history"
    printf 'export HISTFILE="$HOME/.local/state/bash/history"\n' >>"${SANDBOX}/home/${file}"
    run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
    assert_status 0
    if [[ "$(<"${SANDBOX}/home/.local/state/bash/history")" != mine ]]; then
      fail "${file}: moved"
    fi
  done
}

# The same in zsh, set in any of its files (ZDOTDIR's ones, which zsh reads until logging out),
# without the command to move it; bash's history, which they don't set, goes back
function test_uninstall_keeps_a_zsh_history_the_user_points_to() {
  local file
  for file in .config/zsh/.zshrc .config/zsh/.zshenv .config/zsh/.zlogin .zlogin; do
    rm -rf -- "${SANDBOX:?}/home"
    mkdir -- "${SANDBOX}/home"
    install
    mkdir -p -- "${SANDBOX}/home/.local/state/zsh"
    printf 'mine\n' >"${SANDBOX}/home/.local/state/zsh/history"
    mkdir -p -- "${SANDBOX}/home/.local/state/bash"
    printf 'bash\n' >"${SANDBOX}/home/.local/state/bash/history"
    printf 'HISTFILE="$HOME/.local/state/zsh/history"\n' >>"${SANDBOX}/home/${file}"
    run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
    assert_status 0
    if [[ "$(<"${SANDBOX}/home/.local/state/zsh/history")" != mine ]]; then
      fail "${file}: moved"
    fi
    assert_file_contains .bash_history bash
    assert_output_contains "~/${file} sets HISTFILE: ~/.local/state/zsh/history is left as"
    assert_output_not_contains 'mv '
  done
}

function test_history_left_alone_when_off() {
  # om818_history=off: the shells keep their own history; nothing copied, nothing reported
  home_file .bash_history 'ls'
  home_file .config/om818/config.sh 'om818_history=off'
  install
  if [[ -e "${SANDBOX}/home/.local/state/bash/history" ]]; then fail 'history copied'; fi
  run "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_not_contains '.bash_history'
}

function test_read_only_old_history() {
  # A read-only old file: the copy can still be written
  home_file .bash_history 'ls'
  chmod 400 "${SANDBOX}/home/.bash_history"
  install
  if [[ "$(ls -l -- "${SANDBOX}/home/.local/state/bash/history")" != -rw-------* ]]; then
    fail "copy: $(ls -l -- "${SANDBOX}/home/.local/state/bash/history")"
  fi
}

function test_a_cut_startup_file_keeps_its_copy() {
  # Rewriting ~/.bashrc fails half-way (e.g. a full disk): its full copy is kept, private, out of
  # the state folder (which uninstall removes)
  home_file .bashrc '# mine
export TOKEN=secret'
  chmod 600 "${SANDBOX}/home/.bashrc"
  fake_tool cat 'case "${2:-}" in */startup.tmp.*) head -c 5 -- "$2"; exit 1 ;; esac
exec "'"${TEST_DIR}"'/sysbin/cat" "$@"'
  install
  assert_output_contains 'cannot rewrite ~/.bashrc, which may be cut short'
  assert_output_contains 'is in ~/.om818-.bashrc'
  rm -f -- "${SANDBOX}/bin/cat"
  assert_file_contains .om818-.bashrc 'TOKEN=secret'
  if [[ "$(ls -l -- "${SANDBOX}/home/.om818-.bashrc")" != -rw-------* ]]; then
    fail 'the copy is not private'
  fi
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_file_contains .om818-.bashrc 'TOKEN=secret'
}

function test_reinstall_before_logging_out() {
  # The session still has oh-my-818's ZDOTDIR from before the uninstall: ~/.zshenv gets its line
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  install ZDOTDIR="${SANDBOX}/home/.config/zsh"
  assert_file_contains .zshenv 'export ZDOTDIR='
}

function test_protection_restores_what_was_there() {
  # A file the user had empty, and a group-writable one: as they were once protection is off
  home_file .bashrc '# mine'
  chmod 664 "${SANDBOX}/home/.bashrc"
  mkdir -p -- "${SANDBOX}/home/.config/zsh"
  : >"${SANDBOX}/home/.config/zsh/.zprofile"
  home_file .config/om818/config.sh 'om818_protect_startup_files=on'
  install
  assert_read_only .bashrc .config/zsh/.zprofile .zshrc
  home_file .config/om818/config.sh 'om818_protect_startup_files=off'
  install
  if [[ "$(ls -l -- "${SANDBOX}/home/.bashrc")" != -rw-rw-r--* ]]; then
    fail 'mode not restored'
  fi
  if [[ ! -e "${SANDBOX}/home/.config/zsh/.zprofile" ]]; then
    fail "the user's empty file removed"
  fi
  if [[ -e "${SANDBOX}/home/.zshrc" ]]; then fail 'a guard left'; fi
}

# Through sudo, root keeping the user's home folder: refused before anything is written there, by
# the installer and by om818 (here id says 0; the home folder is the user's)
function test_refuses_root_in_a_users_home() {
  install
  rm -f -- "${SANDBOX}/home/.profile"
  fake_tool id 'if [ "$*" = -u ]; then echo 0; else exec "'"${TEST_DIR}"'/sysbin/id" "$@"; fi'
  run sh "${FIXTURE}/install.sh"
  assert_status 1
  assert_output_contains 'error: run the installer as yourself, without sudo'
  run "${SANDBOX}/home/.local/share/om818/bin/om818" install
  assert_status 1
  assert_output_contains "error: run it as yourself, without sudo: ~ isn't root's"
  if [[ -e "${SANDBOX}/home/.profile" ]]; then fail 'a startup file written'; fi
}

# A mistyped option (--tmp for --temp): an error, not a regular install into the home folder
function test_unknown_argument() {
  run sh "${FIXTURE}/install.sh" --tmp
  assert_status 2
  assert_output_contains 'error: unknown argument: --tmp'
  if [[ -e "${SANDBOX}/home/.local" ]]; then fail 'something made'; fi
}

function test_install_without_shell_variable() {
  # Containers, Dockerfile RUN lines: no SHELL
  run env -u SHELL sh "${FIXTURE}/install.sh"
  assert_status 0
  assert_file_contains .bashrc '/om818/om818.plugin.bash"; fi # om818'
  assert_output_not_contains 'Your login shell'
  # The whole report (dash and busybox stopped it after its first rows, then "All good.")
  run env -u SHELL sh "${SANDBOX}/home/.local/share/om818/bin/om818" status
  assert_output_contains 'startup files'
}

# A login shell that is neither zsh nor bash (useradd's /bin/sh): said, with the command to switch
function test_says_when_the_login_shell_is_neither() {
  install SHELL=/bin/sh
  assert_output_contains 'Your login shell is /bin/sh: oh-my-818 runs in zsh or bash.'
  assert_output_matches 'chsh -s /[^ ]+ \(else: sudo usermod -s /[^ ]+ [^ ]+\)'
  assert_output_matches 'For now: exec /[^ ]+ -l'
  install
  assert_output_not_contains 'Your login shell'
}

# A history file the user's startup files set (zsh-newuser-install's ~/.histfile, a bash "eternal
# history"): not looked for (no shell run to find it), but named with the command to copy it; the
# default file still copied
function test_names_a_history_set_with_histfile() {
  home_file .zshrc 'HISTFILE=~/.histfile'
  home_file .histfile ': 1:0;zsh-old-command'
  home_file .bashrc 'HISTFILE="$HOME/.bash_eternal"'
  home_file .bash_history 'bash-old-command'
  install
  assert_output_contains "~/.zshrc sets HISTFILE: that zsh history isn't copied"
  assert_output_contains 'To bring it in: cat <that file> >>~/.local/state/zsh/history'
  assert_output_contains "~/.bashrc sets HISTFILE: that bash history isn't copied"
  assert_file_contains .local/state/bash/history 'bash-old-command'
  if grep -qs 'zsh-old-command' "${SANDBOX}/home/.local/state/zsh/history"; then
    fail '~/.histfile copied'
  fi
}

function test_unreadable_old_history() {
  # e.g. root's, from a root shell that kept this HOME: the install goes on
  home_file .bash_history 'ls'
  chmod 000 "${SANDBOX}/home/.bash_history"
  install
  assert_output_contains 'cannot read ~/.bash_history'
  chmod 600 "${SANDBOX}/home/.bash_history"
}

function test_om818_through_a_link() {
  install
  mkdir -p -- "${SANDBOX}/home/bin"
  ln -s -- ../.local/share/om818/bin/om818 "${SANDBOX}/home/bin/om818"
  run "${SANDBOX}/home/bin/om818" version
  assert_output_eq 'v0.1.0'
}

function test_protection_of_a_linked_file() {
  # A startup file linked into a dotfiles folder: its target keeps its mode (a link's own mode is
  # rwxrwxrwx: taken for the file's, protection off would make it writable by anyone)
  mkdir -p -- "${SANDBOX}/home/dotfiles"
  printf '# mine\n' >"${SANDBOX}/home/dotfiles/bashrc"
  chmod 644 "${SANDBOX}/home/dotfiles/bashrc"
  ln -s -- dotfiles/bashrc "${SANDBOX}/home/.bashrc"
  home_file .config/om818/config.sh 'om818_protect_startup_files=on'
  install
  home_file .config/om818/config.sh 'om818_protect_startup_files=off'
  install
  if [[ "$(ls -l -- "${SANDBOX}/home/dotfiles/bashrc")" != -rw-r--r--* ]]; then
    fail "the linked file's mode changed: $(ls -l -- "${SANDBOX}/home/dotfiles/bashrc")"
  fi
}

# A temporary install (install.sh --temp): the home folder untouched (but the shell's usual
# history), two sessions sharing it, removed once the last one exits
function test_temporary_install() {
  local run="${SANDBOX}/run" folder="${SANDBOX}/run/om818-temp${TEMP_NS}" left
  tty_available || return 0
  mkdir -m 700 -- "$run"
  # (a login shell that is neither: zsh, also for the shells it starts)
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=/bin/sh sh ${FIXTURE}/install.sh --temp"
  tty_type 'echo "temp=${OM818_TEMP##*/} ${SHELL##*/}"; om818 update'
  if ! wait_for tty_has 'not available in a temporary install'; then fail 'om818 update ran'; fi
  tty_read
  assert_output_contains "temp=om818-temp${TEMP_NS} zsh"
  # Not again inside it, nor the regular install; a subshell's exit isn't the shell's
  tty_type "sh ${FIXTURE}/install.sh --temp; sh ${FIXTURE}/install.sh; (exit)"
  if ! wait_for tty_has 'runs a temporary install'; then fail 'install.sh ran inside'; fi
  if [[ ! -d "$folder" ]]; then fail 'removed by a subshell'; fi
  # A second session: the same install (OM818_REF said to be left out), its setup as it is (here
  # its config.sh edited meanwhile)
  printf '# mine\n' >>"${folder}/config/config.sh"
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_RUNTIME_DIR=${run} OM818_REF=main sh ${FIXTURE}/install.sh --temp"
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail 'no second session'; fi
  tty_read
  assert_output_not_contains 'Cloning'
  assert_output_contains 'OM818_REF left out'
  if ! grep -qx '# mine' -- "${folder}/config/config.sh"; then fail 'config.sh written again'; fi
  left="$(ls -- "${folder}/sessions")"
  if [[ "$(wc -l <<<"$left")" -ne 2 ]]; then fail "sessions: ${left}"; fi
  # Nothing written in the home folder but the history
  left="$(cd -- "${SANDBOX}/home" && find . -mindepth 1 ! -name .zsh_history)"
  if [[ -n "$left" ]]; then fail "written in the home folder: ${left}"; fi
  assert_file_contains .zsh_history 'echo "temp=${OM818_TEMP##*/} ${SHELL##*/}"'
  # The first session exits: still there; the last one: removed
  run tmux -S "$TMUX_SOCKET" send-keys -t :0 'exit' Enter
  if ! wait_for tty_window_gone 0; then fail 'the first session still runs'; fi
  if [[ ! -x "${folder}/om818/bin/om818" ]]; then fail 'removed with a session left'; fi
  run tmux -S "$TMUX_SOCKET" send-keys -t :1 'exit' Enter
  if ! wait_for eval '[[ ! -e "$folder" ]]'; then fail "left: $(ls -A -- "$folder")"; fi
}

function test_temporary_install_refuses_a_foreign_folder() {
  # Without a terminal: said so, nothing made
  mkdir -m 700 -- "${SANDBOX}/run"
  run XDG_RUNTIME_DIR="${SANDBOX}/run" sh "${FIXTURE}/install.sh" --temp
  assert_status 1
  assert_output_contains 'run it in a terminal'
  if [[ -e "${SANDBOX}/run/om818-temp${TEMP_NS}" ]]; then fail 'a folder made'; fi
  # Its folder made beforehand, open to others (e.g. by another user, in /tmp): refused, untouched
  tty_available || return 0
  mkdir -m 755 -- "${SANDBOX}/run/om818-temp${TEMP_NS}"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${SANDBOX}/run sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err
    echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "not refused: $(tty_read && echo "$OUTPUT")"; fi
  # (its message in a file: a long line would wrap in the terminal)
  if ! grep -q 'is not a private folder of yours' "${SANDBOX}/err"; then
    fail "message: $(<"${SANDBOX}/err")"
  fi
  if [[ -n "$(ls -A -- "${SANDBOX}/run/om818-temp${TEMP_NS}")" ]]; then fail 'written into it'; fi
}

# Another user's shell started from it (root through sudo -s, keeping SHELL): their own, not
# oh-my-818 (here: the files made for another uid)
function test_temporary_install_other_user() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  sed -i.orig "s/ $(id -u) \]/ 99999 ]/" "${run}/om818-temp${TEMP_NS}/bin/bash" \
    "${run}/om818-temp${TEMP_NS}/bashrc" \
    "${run}/om818-temp${TEMP_NS}/zdotdir/.zshrc"
  tty_type '"$SHELL"'
  tty_type 'echo "other=${om818_shell:-none}"'
  if ! wait_for tty_has '^other=none$'; then fail 'oh-my-818 for another user'; fi
  # (zsh, keeping ZDOTDIR)
  tty_type 'ZDOTDIR="$OM818_TEMP/zdotdir" zsh --no-globalrcs -i'
  tty_type 'echo "zsh=${om818_shell:-none}"'
  if ! wait_for tty_has '^zsh=none$'; then fail 'oh-my-818 for another user (zsh)'; fi
}

# The line typed in a login shell, then the connection drops (the terminal goes): removed. Without
# XDG_RUNTIME_DIR, in the home folder's cache (/tmp could be taken by another user), by host
function test_temporary_install_dropped_connection() {
  local shell plain folder
  tty_available || return 0
  folder="${SANDBOX}/home/.cache/om818-temp-$(uname -n)${TEMP_NS}"
  for shell in zsh bash; do
    plain='zsh -f -i'
    if [[ "$shell" == bash ]]; then plain='bash --norc --noprofile -i'; fi
    run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
      -c "${SANDBOX}/home" "env SHELL=$(command -v "$shell") ${plain}"
    sleep 0.5
    run tmux -S "$TMUX_SOCKET" send-keys -l "sh ${FIXTURE}/install.sh --temp"
    run tmux -S "$TMUX_SOCKET" send-keys Enter
    if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail "no ${shell} session"; fi
    # (a job of the session, its process in a subshell: ended by the hang-up, as without
    # oh-my-818)
    tty_type "(sh -c 'echo \$\$ >${SANDBOX}/job; exec sleep 301'; :) &"
    if ! wait_for eval '[[ -s "${SANDBOX}/job" ]]'; then fail 'no job'; fi
    if [[ ! -d "$folder" ]]; then fail "not in ~/.cache: $(ls -A -- "${SANDBOX}/home/.cache")"; fi
    if [[ "$(ls -ld -- "${SANDBOX}/home/.cache")" != drwx------* ]]; then
      fail "${shell}: the cache folder made open to others"
    fi
    run tmux -S "$TMUX_SOCKET" kill-server
    if ! wait_for eval '[[ ! -e "$folder" ]]'; then fail "${shell}: left $(ls -A -- "$folder")"; fi
    # (~/.cache, made for it, gone too)
    if [[ -e "${SANDBOX}/home/.cache" ]]; then fail "${shell}: ~/.cache left"; fi
    if ! wait_for eval '! kill -0 "$(<"${SANDBOX}/job")" 2>/dev/null ||
      [[ "$(ps -o stat= -p "$(<"${SANDBOX}/job")")" == Z* ]]'; then
      kill "$(<"${SANDBOX}/job")"
      fail "${shell}: the job outlived the hang-up"
    fi
    rm -f -- "${SANDBOX}/job"
  done
}

# The same in bash: its usual history never trimmed, and the shells it starts ($SHELL, e.g.
# tmux's) get oh-my-818 too
function test_temporary_install_bash() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  run bash -c 'for ((i = 0; i < 30000; i++)); do echo "$i"; done >~/.bash_history'
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  # (-l, as some tools start it: bash would then ignore --rcfile; also -il and --login)
  tty_type '"$SHELL" -l'
  tty_type 'echo "nested=$om818_shell"'
  if ! wait_for tty_has '^nested=bash$'; then fail 'no oh-my-818 in the nested shell'; fi
  tty_type '"$SHELL" -il'
  tty_type 'echo "il=$om818_shell"'
  if ! wait_for tty_has '^il=bash$'; then fail 'no oh-my-818 in the -il shell'; fi
  tty_type '"$SHELL" --login'
  tty_type 'echo "login=$om818_shell"'
  if ! wait_for tty_has '^login=bash$'; then fail 'no oh-my-818 in the --login shell'; fi
  tty_type 'exit'
  tty_type 'exit'
  tty_type 'exit'
  tty_type 'exit'
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  # (the 30000 lines, then the 10 commands typed in oh-my-818's shells)
  run bash -c 'mapfile -t lines <~/.bash_history; echo "${lines[0]} ${#lines[@]}"'
  assert_output_eq '0 30010'
}

# The commands that change the install are refused inside a temporary one (uninstall would
# rewrite the host's startup files)
function test_temp_refuses_commands() {
  local cmd
  install
  mkdir -m 700 -- "${SANDBOX}/t"
  for cmd in install update rollback uninstall; do
    run OM818_TEMP="${SANDBOX}/t" "${SANDBOX}/home/.local/share/om818/bin/om818" "$cmd"
    assert_status 1
    assert_output_contains "om818 ${cmd}: not available in a temporary install"
  done
  assert_file_contains .bashrc 'om818.plugin.bash'
}

# A failed setup (here the clone) removes the folder; a setup lock whose owner is gone is taken
# over at once
function test_temp_failed_setup() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run" "${run}/om818-temp${TEMP_NS}"
  mkdir -- "${run}/om818-temp${TEMP_NS}/setup.lock"
  printf '999999999\n' >"${run}/om818-temp${TEMP_NS}/setup.lock/pid"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${run} OM818_REPO=${SANDBOX}/none sh ${FIXTURE}/install.sh --temp
    echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "no status: $(tty_read && echo "$OUTPUT")"; fi
  tty_read
  assert_output_contains 'cannot clone'
  if [[ -e "${run}/om818-temp${TEMP_NS}" ]]; then
    fail "left: $(ls -A -- "${run}/om818-temp${TEMP_NS}")"
  fi
}

# zsh: its usual history never trimmed either; the forced settings; status shows neither startup
# files nor leftovers (the old history file is the one in use)
function test_temp_zsh_history() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  run bash -c 'for ((i = 0; i < 30000; i++)); do echo "$i"; done >~/.zsh_history'
  # (the home's zsh files aren't said to be unread: oh-my-818 isn't installed there)
  home_file .zshrc 'alias mine=true'
  tty_start "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp"
  tty_read
  assert_output_not_contains 'no longer reads'
  tty_type "om818 status >${run}/status"
  tty_type 'echo "$om818_update $om818_xdg $om818_tool_completions"'
  if ! wait_for tty_has '^off off off$'; then fail 'settings not forced'; fi
  tty_type 'exit'
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  # (zsh rewrites it at exit in its extended format, ": <time>:0;0": all lines kept)
  run bash -c 'mapfile -t lines <~/.zsh_history; echo "${lines[0]##*;} ${#lines[@]}"'
  assert_output_eq '0 30003'
  OUTPUT="$(<"${run}/status")"
  assert_output_contains 'temporary install, in '
  assert_output_not_contains 'startup files'
  assert_output_not_contains 'old zsh history'
}

# The first line's insert leaves no copy of the file behind (it holds the file's content)
function test_top_insert_leaves_no_copy() {
  home_file .bashrc '# mine'
  install
  if compgen -G "${SANDBOX}/home/.local/state/om818/startup.tmp.*" >/dev/null; then
    fail 'a copy left'
  fi
}

# On a host where oh-my-818 is installed: the temporary install's om818, not the host's
function test_temp_over_an_install() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  install
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  # (the folder's real path: the sandbox's may go through a link, macOS's TMPDIR in /var)
  tty_type 'p="$(command -v om818)"; echo "om818=${p#"$(cd -P -- "$XDG_RUNTIME_DIR" && pwd -P)"}"'
  if ! wait_for tty_has "^om818=/om818-temp${TEMP_NS}/om818/bin/om818\$"; then
    fail "the host's om818: $(tty_read && echo "$OUTPUT")"
  fi
}

# A folder left by sessions gone (killed: no exit hook) holding a broken install: set up anew
function test_temp_left_by_killed_sessions() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run" "${run}/om818-temp${TEMP_NS}"
  mkdir -p -- "${run}/om818-temp${TEMP_NS}/sessions" "${run}/om818-temp${TEMP_NS}/om818/.git"
  : >"${run}/om818-temp${TEMP_NS}/sessions/999999999"
  tty_start "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp"
  tty_read
  assert_output_contains 'Cloning'
}

# A setup running in another session is waited for (said after 3 s); a setup lock without a pid
# (its owner killed as it made it) is taken over after 5 s
function test_temp_waits_for_another_setup() {
  local run="${SANDBOX}/run" pid
  tty_available || return 0
  mkdir -m 700 -- "$run" "${run}/om818-temp${TEMP_NS}"
  mkdir -- "${run}/om818-temp${TEMP_NS}/setup.lock"
  sleep 4 &
  pid="$!"
  printf '%s\n' "$pid" >"${run}/om818-temp${TEMP_NS}/setup.lock/pid"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp; echo status=\$?; sleep 30"
  if ! wait_for tty_has 'Waiting for another session'; then fail 'not waiting'; fi
  if tty_has 'Cloning'; then fail 'set up while another one runs'; fi
  # (its end reaped here: a zombie would still answer kill -0)
  wait "$pid" || true
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail 'no prompt once it ended'; fi
  run tmux -S "$TMUX_SOCKET" kill-server
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  run="${SANDBOX}/run2"
  mkdir -m 700 -- "$run" "${run}/om818-temp${TEMP_NS}"
  mkdir -- "${run}/om818-temp${TEMP_NS}/setup.lock"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp; echo status=\$?; sleep 30"
  if ! wait_for tty_has 'Waiting for another session'; then fail 'not waiting (no pid)'; fi
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail 'not taken over'; fi
}

# A release without temporary installs (e.g. OM818_REF, or the latest being older): refused,
# nothing left
function test_temp_refuses_an_old_release() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  sed -i.orig 's/OM818_TEMP/OM818_OLD/g' "${FIXTURE}/lib/common.sh"
  rm -f -- "${FIXTURE}/lib/common.sh.orig"
  git_ -C "$FIXTURE" commit -qam 'an old release'
  git_ -C "$FIXTURE" tag v0.2.0
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp; echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "no status: $(tty_read && echo "$OUTPUT")"; fi
  tty_read
  assert_output_contains 'this release has no temporary install'
  if [[ -e "${run}/om818-temp${TEMP_NS}" ]]; then
    fail "left: $(ls -A -- "${run}/om818-temp${TEMP_NS}")"
  fi
}

# OM818_TEMP that isn't the user's own absolute folder (relative, a link): ignored by the shells
# (the bash plugin doesn't source its env.sh first), and by om818
function test_temp_variable_checked() {
  local value shell
  install
  mkdir -m 700 -- "${SANDBOX}/t"
  mkdir -- "${SANDBOX}/t/state"
  printf 'echo sourced\n' >"${SANDBOX}/t/state/env.sh"
  ln -s -- "${SANDBOX}/t" "${SANDBOX}/link"
  for value in t "${SANDBOX}/link"; do
    for shell in zsh bash; do
      shell_i "$shell" OM818_TEMP="$value" 'printf "%s\n" "${OM818_TEMP:-dropped}"'
      assert_output_eq 'dropped'
    done
    run OM818_TEMP="$value" "${SANDBOX}/home/.local/share/om818/bin/om818" rollback
    assert_output_not_contains 'temporary install'
  done
  # (the bash plugin alone, as a plugin manager loads it: the environment not loaded before)
  printf 'source ~/.local/share/om818/om818.plugin.bash\n' >"${SANDBOX}/home/.bashrc"
  for value in t "${SANDBOX}/link"; do
    bash_i OM818_TEMP="$value" 'printf "%s\n" "${OM818_TEMP:-dropped}"'
    assert_output_eq 'dropped'
  done
}

# Neither zsh nor bash 4.4+: said before anything is cloned (the shells' probe quiet, e.g. a bash
# 3.2 failing on (( )), or none at all)
function test_needs_a_shell() {
  local tool arg
  mkdir -p -- "${SANDBOX}/sysbin"
  for tool in "${TEST_DIR}/sysbin"/*; do
    if [[ "$tool" != */zsh ]]; then ln -s -- "$(readlink -- "$tool")" "${SANDBOX}/sysbin/"; fi
  done
  fake_tool bash 'echo "bash: too old" >&2; exit 1'
  for arg in '' --temp; do
    run PATH="${SANDBOX}/bin:${SANDBOX}/sysbin" SHELL=/bin/sh \
      sh "${FIXTURE}/install.sh" ${arg:+"$arg"}
    assert_status 1
    assert_output_eq 'error: oh-my-818 needs zsh, or bash 4.4 or newer: install one'
    if [[ -e "${SANDBOX}/home/.local" ]]; then fail 'something made'; fi
  done
}

# The folder's parent stays, even empty: XDG_RUNTIME_DIR may be a folder the user made
function test_temp_keeps_the_runtime_folder() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp"
  tty_type 'exit'
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  if [[ ! -d "$run" ]]; then fail 'XDG_RUNTIME_DIR removed'; fi
}

# A folder others can write (here XDG_CACHE_HOME, as /tmp): never the temporary install's parent;
# an XDG_RUNTIME_DIR open to others: not used
function test_temp_needs_a_closed_parent() {
  tty_available || return 0
  mkdir -m 1777 -- "${SANDBOX}/open"
  mkdir -m 755 -- "${SANDBOX}/run"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${SANDBOX}/run XDG_CACHE_HOME=${SANDBOX}/open \
    sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err; echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "not refused: $(tty_read && echo "$OUTPUT")"; fi
  if ! grep -q 'others can change it (or a folder above it)' "${SANDBOX}/err"; then
    fail "message: $(<"${SANDBOX}/err")"
  fi
  if [[ -e "${SANDBOX}/run/om818-temp${TEMP_NS}" ]]; then
    fail 'XDG_RUNTIME_DIR open to others used'
  fi
  # Its group's write access too; a folder that can't be made in it: said so
  mkdir -m 770 -- "${SANDBOX}/group"
  mkdir -m 500 -- "${SANDBOX}/read-only"
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_CACHE_HOME=${SANDBOX}/group sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err
    echo group=\$?; env XDG_CACHE_HOME=${SANDBOX}/read-only sh ${FIXTURE}/install.sh --temp \
    2>${SANDBOX}/err2; echo read-only=\$?; sleep 30"
  if ! wait_for tty_has '^read-only=1$'; then fail "not refused: $(tty_read && echo "$OUTPUT")"; fi
  if ! tty_has '^group=1$'; then fail 'a folder its group can change used'; fi
  if ! grep -q 'cannot make' "${SANDBOX}/err2"; then fail "message: $(<"${SANDBOX}/err2")"; fi
  # A link to a folder of the user's: used
  mkdir -m 700 -- "${SANDBOX}/cache"
  ln -s -- "${SANDBOX}/cache" "${SANDBOX}/link"
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_CACHE_HOME=${SANDBOX}/link sh ${FIXTURE}/install.sh --temp"
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then
    fail "not used: $(tty_read && echo "$OUTPUT")"
  fi
}

# A setup lock that can't be made (a full disk; here a file in its place): an error at once
function test_temp_setup_lock_cannot_be_made() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run" "${run}/om818-temp${TEMP_NS}"
  : >"${run}/om818-temp${TEMP_NS}/setup.lock"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${run} sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err
    echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "no status: $(tty_read && echo "$OUTPUT")"; fi
  if ! grep -q 'cannot write in' "${SANDBOX}/err"; then fail "message: $(<"${SANDBOX}/err")"; fi
}

# The exit hook globs as it needs, whatever the user's options: noglob (bash's set -f, zsh's
# no_glob) doesn't make a session remove the folder others use, failglob doesn't keep the last one
# from removing it
function test_temp_exit_whatever_the_glob_options() {
  local run="${SANDBOX}/run" folder="${SANDBOX}/run/om818-temp${TEMP_NS}" i left
  tty_available || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_RUNTIME_DIR=${run} SHELL=$(command -v zsh) sh ${FIXTURE}/install.sh --temp"
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  if ! wait_for eval '[[ "$(ls -- "${folder}/sessions" 2>/dev/null | wc -l)" -eq 3 ]]'; then
    fail "sessions: $(ls -- "${folder}/sessions")"
  fi
  # (the setup's last steps done: its lock gone)
  if ! wait_for eval '[[ ! -e "${folder}/setup.lock" ]]'; then fail 'setup.lock left'; fi
  for i in 0 1; do
    if [[ "$i" -eq 0 ]]; then
      run tmux -S "$TMUX_SOCKET" send-keys -t :0 -l 'set -f; exit'
    else
      run tmux -S "$TMUX_SOCKET" send-keys -t :1 -l 'setopt no_glob; exit'
    fi
    run tmux -S "$TMUX_SOCKET" send-keys -t ":${i}" Enter
    # (once its shell is gone, its exit hook is done: a removal would be under way meanwhile)
    if ! wait_for tty_window_gone "$i"; then fail "window ${i}: still open"; fi
    left="$(find "${folder}/sessions" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
    if [[ "$left" -ne $((2 - i)) || ! -x "${folder}/om818/bin/om818" ]]; then
      fail "window ${i}: removed with a session left: $(ls -A -- "$run")"
    fi
  done
  run tmux -S "$TMUX_SOCKET" send-keys -t :2 -l 'shopt -s failglob; exit'
  run tmux -S "$TMUX_SOCKET" send-keys -t :2 Enter
  if ! wait_for eval '[[ ! -e "$folder" ]]'; then fail "left: $(ls -A -- "$folder")"; fi
}

# A temporary install on a host where oh-my-818 runs: the host's variables (its env.sh's, for the
# host's tools) stay in its shells
function test_temp_keeps_the_hosts_variables() {
  local t="${SANDBOX}/t"
  install
  mkdir -m 700 -- "$t"
  mkdir -- "${t}/config"
  printf '%s\n' om818_update=off om818_xdg=off om818_tool_completions=off >"${t}/config/config.sh"
  run OM818_TEMP="$t" "${SANDBOX}/home/.local/share/om818/bin/om818" env --quiet
  assert_status 0
  run CARGO_HOME=/host OM818_ENV_VARS=CARGO_HOME sh -c '. "$1"; echo "cargo=${CARGO_HOME:-}"' \
    sh "${t}/state/env.sh"
  assert_output_eq 'cargo=/host'
}

# A folder others can write further up (here two levels above the cache): they could swap the tree
# (others' write access only, as group's is checked at the parent); a private XDG_RUNTIME_DIR there
# not used either (the cache instead); a missing cache not made there. Then a folder above that is
# another user's
function test_temp_needs_closed_folders_above() {
  tty_available || return 0
  mkdir -m 757 -- "${SANDBOX}/open"
  mkdir -m 755 -- "${SANDBOX}/open/me"
  mkdir -m 700 -- "${SANDBOX}/open/me/cache" "${SANDBOX}/open/me/run"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${SANDBOX}/open/me/run XDG_CACHE_HOME=${SANDBOX}/open/me/cache \
    sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err; echo status=\$?
    env XDG_CACHE_HOME=${SANDBOX}/open/me/new sh ${FIXTURE}/install.sh --temp 2>/dev/null
    echo new=\$?; sleep 30"
  if ! wait_for tty_has '^new=1$'; then fail "not refused: $(tty_read && echo "$OUTPUT")"; fi
  if ! tty_has '^status=1$'; then fail 'not refused'; fi
  if ! grep -q 'others can change it (or a folder above it)' "${SANDBOX}/err"; then
    fail "message: $(<"${SANDBOX}/err")"
  fi
  if [[ -n "$(ls -A -- "${SANDBOX}/open/me/cache")$(ls -A -- "${SANDBOX}/open/me/run")" ]]; then
    fail 'a folder made in it'
  fi
  if [[ -e "${SANDBOX}/open/me/new" ]]; then fail 'the cache made there'; fi
  # (the cache instead of such an XDG_RUNTIME_DIR)
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_RUNTIME_DIR=${SANDBOX}/open/me/run sh ${FIXTURE}/install.sh --temp"
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then
    fail "not in the cache: $(tty_read && echo "$OUTPUT")"
  fi
  if [[ -n "$(ls -A -- "${SANDBOX}/open/me/run")" ]]; then fail 'XDG_RUNTIME_DIR used'; fi
  # (another user's folder, as ls shows it)
  mkdir -m 755 -- "${SANDBOX}/foreign"
  mkdir -m 700 -- "${SANDBOX}/foreign/cache"
  fake_tool ls 'out="$('"${TEST_DIR}/sysbin/ls"' "$@")" || exit
if [ -z "$out" ]; then exit 0; fi
case "$*" in
*/foreign) printf "%s\n" "$out" | sed "s/^\([^ ]*  *[^ ]*  *\)[0-9][0-9]*/\14242/" ;;
*) printf "%s\n" "$out" ;;
esac'
  run tmux -S "$TMUX_SOCKET" new-window \
    "env XDG_CACHE_HOME=${SANDBOX}/foreign/cache sh ${FIXTURE}/install.sh --temp 2>/dev/null
    echo foreign=\$?; sleep 30"
  if ! wait_for tty_has '^foreign=1$'; then fail "not refused: $(tty_read && echo "$OUTPUT")"; fi
}

# A host name holding / or blanks: one folder name; the shells' wrapper (SHELL) a bash, even after
# a first zsh session; its rewrite of -l only in the leading options
function test_temp_host_name_and_wrapper() {
  local run="${SANDBOX}/run" folder
  tty_available || return 0
  folder="${SANDBOX}/home/.cache/om818-temp-a_.._b_c${TEMP_NS}"
  mkdir -m 700 -- "$run"
  fake_tool uname 'if [ "${1:-}" = -n ]; then echo "a/../b c"; else
  exec '"${TEST_DIR}/sysbin/uname"' "$@"
fi'
  # (SHELL another temporary install's wrapper, e.g. inherited by a terminal one started: skipped)
  mkdir -p -- "${SANDBOX}/w/om818-temp-x/bin"
  ln -s -- "${SANDBOX}/bin/bash" "${SANDBOX}/w/om818-temp-x/bin/bash"
  tty_start "env XDG_RUNTIME_DIR=${SANDBOX}/none SHELL=${SANDBOX}/w/om818-temp-x/bin/bash \
    sh ${FIXTURE}/install.sh --temp"
  tty_type 'echo "shell=$om818_shell"'
  if ! wait_for tty_has '^shell=zsh$'; then fail 'the wrapper picked'; fi
  if [[ ! -d "${folder}" ]]; then
    fail "folder: $(ls -A -- "${SANDBOX}/home/.cache")"
  fi
  if ! grep -q "bash' --rcfile" -- "${folder}/bin/bash"; then
    fail "wrapper: $(<"${folder}/bin/bash")"
  fi
  # status hides the host's name in the folder's, the same way rewritten
  tty_type "om818 status >${SANDBOX}/status.tmp 2>&1; mv ${SANDBOX}/status.tmp ${SANDBOX}/status"
  if ! wait_for test -e "${SANDBOX}/status"; then fail 'no status'; fi
  if grep -q 'a_.._b_c' "${SANDBOX}/status" || ! grep -q 'temp-<host>' "${SANDBOX}/status"; then
    fail "host shown: $(<"${SANDBOX}/status")"
  fi
  run "${folder}/bin/bash" -c 'printf "<%s>" "$@"' _ -l keep
  assert_output_eq '<-l><keep>'
  printf '%s\n' 'printf "<%s>" "$@"' >"${SANDBOX}/args.sh"
  run "${folder}/bin/bash" "${SANDBOX}/args.sh" -l keep
  assert_output_eq '<-l><keep>'
  # (-il and --login, also in a group with -c or after -o …: not a login bash, which would ignore
  # --rcfile)
  for arg in -il -li --login -lc -ilc '-o vi -l -c' '-eo pipefail -lc' '-oe pipefail -lc'; do
    # shellcheck disable=SC2086 # options: split on purpose
    run "${folder}/bin/bash" $arg \
      'if shopt -q login_shell; then echo login; else echo plain; fi'
    if [[ "$OUTPUT" != *plain* ]]; then fail "${arg}: a login shell"; fi
  done
}

# The wrapper keeps the arguments after - (bash's end of options)
function test_temp_wrapper_dash() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  printf '%s\n' 'printf "<%s>" "$@"' >"${SANDBOX}/args.sh"
  run sh -c '"$1" -s - -l keep <"$2"' _ "${run}/om818-temp${TEMP_NS}/bin/bash" "${SANDBOX}/args.sh"
  assert_output_eq '<-l><keep>'
}

# The folders checked as given: a link in the path is refused (it was resolved before: one there
# now was put there since, e.g. by another user swapping it)
function test_temp_closed_refuses_a_link() {
  sed -n '/^temp_closed()/,/^}/p' "${FIXTURE}/install.sh" >"${SANDBOX}/closed.sh"
  mkdir -m 700 -- "${SANDBOX}/real"
  ln -s -- "${SANDBOX}/real" "${SANDBOX}/link"
  run sh -c '. "$1"; temp_closed "$2"; echo "real=$?"; temp_closed "$3"; echo "link=$?"' _ \
    "${SANDBOX}/closed.sh" "$(cd -P -- "${SANDBOX}/real" && pwd -P)" "${SANDBOX}/link"
  assert_output_eq $'real=0\nlink=1'
}

# The cache reached through a link in a folder others can write: used by its real path (the
# link could be replaced)
function test_temp_through_a_link() {
  local real
  tty_available || return 0
  mkdir -m 777 -- "${SANDBOX}/open"
  mkdir -m 700 -- "${SANDBOX}/real"
  ln -s -- "${SANDBOX}/real" "${SANDBOX}/open/link"
  tty_start "env XDG_RUNTIME_DIR=${SANDBOX}/none XDG_CACHE_HOME=${SANDBOX}/open/link \
    sh ${FIXTURE}/install.sh --temp"
  # (the sandbox's own path may go through a link too: macOS's TMPDIR, in /var)
  real="$(cd -P -- "${SANDBOX}/real" && pwd -P)"
  tty_type "[[ \"\${OM818_TEMP%/*}\" == '${real}' ]] && echo real-path"
  if ! wait_for tty_has '^real-path$'; then fail "$(tty_read && echo "$OUTPUT")"; fi
}

# A setup lock taken when a session tries it, released before it looks again (two sessions
# started together): waited for, not taken for a folder it can't write in
function test_temp_lock_released_meanwhile() {
  local folder="${SANDBOX}/run/om818-temp${TEMP_NS}"
  tty_available || return 0
  mkdir -m 700 -- "${SANDBOX}/run" "$folder"
  mkdir -- "${folder}/sessions" "${folder}/setup.lock"
  printf '%s\n' "$$" >"${folder}/setup.lock/pid"
  # (its owner releasing it right after mkdir found it taken, once)
  fake_tool mkdir 'if [ "$1" = -- ] && [ "${2##*/}" = setup.lock ] && [ -d "$2" ] &&
  [ ! -e "$2.seen" ]; then
  : >"$2.seen"
  rm -rf -- "$2"
  exit 1
fi
exec '"${TEST_DIR}/sysbin/mkdir"' "$@"'
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env XDG_RUNTIME_DIR=${SANDBOX}/run sh ${FIXTURE}/install.sh --temp 2>${SANDBOX}/err
    echo status=\$?; sleep 30"
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then
    fail "no session: $(<"${SANDBOX}/err")"
  fi
}

# The line run from a shell that doesn't pass the hang-up on (a script, `ssh -t host sh -c …`): bash
# only reads an end of file, then hangs its jobs up itself
function test_temporary_install_dropped_connection_eof() {
  local run="${SANDBOX}/run"
  tty_available || return 0
  mkdir -m 700 -- "$run"
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 -c "${SANDBOX}/home" \
    "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash \
    sh -c 'sh ${FIXTURE}/install.sh --temp; :'"
  if ! wait_for tty_has '^[0-9][0-9]:[0-9][0-9] [$#]$'; then fail 'no session'; fi
  tty_type "(sh -c 'echo \$\$ >${SANDBOX}/job; exec sleep 301'; :) &"
  if ! wait_for eval '[[ -s "${SANDBOX}/job" ]]'; then fail 'no job'; fi
  run tmux -S "$TMUX_SOCKET" kill-server
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  if ! wait_for eval '! kill -0 "$(<"${SANDBOX}/job")" 2>/dev/null ||
    [[ "$(ps -o stat= -p "$(<"${SANDBOX}/job")")" == Z* ]]'; then
    kill "$(<"${SANDBOX}/job")"
    fail 'the job outlived the hang-up'
  fi
}

# A plain exit leaves bash's jobs running, as bash does (only a terminal gone hangs them up)
function test_temp_bash_exit_keeps_the_jobs() {
  local run="${SANDBOX}/run" job
  tty_available || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${SANDBOX}/bin/bash sh ${FIXTURE}/install.sh --temp"
  tty_type "sh -c 'echo \$\$ >${SANDBOX}/job; exec sleep 302' &"
  if ! wait_for eval '[[ -s "${SANDBOX}/job" ]]'; then fail 'no job'; fi
  job="$(<"${SANDBOX}/job")"
  tty_type 'exit'
  if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail 'not removed'; fi
  sleep 0.5
  if ! kill -0 "$job" 2>/dev/null; then fail 'the job ended with the shell'; fi
  kill "$job"
}

# An XDG_CACHE_HOME not made yet, written with a final /: made, used
function test_temp_cache_with_a_final_slash() {
  tty_available || return 0
  tty_start "env XDG_RUNTIME_DIR=${SANDBOX}/none XDG_CACHE_HOME=${SANDBOX}/cache/ \
    sh ${FIXTURE}/install.sh --temp"
  if ! compgen -G "${SANDBOX}/cache/om818-temp-*" >/dev/null; then fail 'not made'; fi
}

# The last shell's exit hook, the folder already gone (removed by another shell exiting with it):
# no wait for its lock
function test_temp_exit_after_the_folder_went() {
  install
  mkdir -m 700 -- "${SANDBOX}/t"
  mkdir -- "${SANDBOX}/t/sessions"
  bash_i OM818_TEMP="${SANDBOX}/t" 'rm -rf -- "$OM818_TEMP"; SECONDS=0; _om818_temp_exit
    echo "took=$SECONDS"'
  assert_output_contains 'took=0'
}

# A startup file with bytes of another encoding (Latin-1) and a NUL: uninstall keeps every one of
# its lines (GNU grep, in a UTF-8 locale, would take it for binary and drop them)
function test_uninstall_keeps_lines_of_another_encoding() {
  local out
  printf '# mine\nexport NAME=Ren\351\n' >"${SANDBOX}/home/.bashrc"
  # The NUL only where grep keeps it: busybox's (Alpine) cuts a line there
  out="$(printf 'a\000b\n' | LC_ALL=C "${TEST_DIR}/sysbin/grep" -a -v x | od -An -c)"
  if [[ "$out" == *'\0'* ]]; then
    printf 'alias x=\000y\n' >>"${SANDBOX}/home/.bashrc"
  fi
  cp -- "${SANDBOX}/home/.bashrc" "${SANDBOX}/bashrc.before"
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0
  if ! cmp -s -- "${SANDBOX}/home/.bashrc" "${SANDBOX}/bashrc.before"; then
    fail "~/.bashrc changed: $(od -c "${SANDBOX}/home/.bashrc" | head -5)"
  fi
}

# ~/.zshenv with its line, on a machine without oh-my-818's .zshrc (dotfiles shared with it, or
# its install failed): zsh still reads ~/.zshrc, not an empty folder
function test_zdotdir_only_with_its_zshrc() {
  install
  run zsh -c 'print -r -- "${ZDOTDIR:-none}"'
  assert_output_eq "${SANDBOX}/home/.config/zsh"
  rm -f -- "${SANDBOX}/home/.config/zsh/.zshrc"
  run zsh -c 'print -r -- "${ZDOTDIR:-none}"'
  assert_output_eq 'none'
}

# A system zshenv setting ZDOTDIR to ~/.config/zsh only while the home has no zsh file (Alpine's):
# the line is added anyway, as the ~/.zshenv the install makes stops it
function test_zdotdir_line_when_the_system_sets_it() {
  fake_tool zsh 'for f in .zshenv .zprofile .zshrc .zlogin; do
  if [ -e "$HOME/$f" ]; then exec '"${TEST_DIR}/sysbin/zsh"' "$@"; fi
done
if [ -z "${ZDOTDIR:-}" ]; then export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"; fi
exec '"${TEST_DIR}/sysbin/zsh"' "$@"'
  install
  run zsh -c 'print -r -- "${ZDOTDIR:-none}"'
  assert_output_eq "${SANDBOX}/home/.config/zsh"
}

# VS Code's terminal exports ZDOTDIR=$HOME: the install is the same as elsewhere. Set on purpose
# in ~/.zshenv, it stays
function test_zdotdir_set_to_home() {
  home_file .zshrc 'alias ll="ls -l"'
  install ZDOTDIR="${SANDBOX}/home"
  assert_file_contains .zshenv 'export ZDOTDIR='
  assert_file_contains .config/zsh/.zshrc ' # om818'
  if grep -q ' # om818$' "${SANDBOX}/home/.zshrc"; then fail 'added to ~/.zshrc'; fi
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0

  home_file .zshenv 'export ZDOTDIR="$HOME"'
  install
  assert_file_contains .zshrc ' # om818'
  if grep -q 'ZDOTDIR=.* # om818$' "${SANDBOX}/home/.zshenv"; then fail 'ZDOTDIR line added'; fi
}

# Uninstalling with the user's own line setting ZDOTDIR to ~/.config/zsh: zsh stays on that folder
function test_uninstall_with_your_own_zdotdir_line() {
  home_file .zshenv 'export ZDOTDIR="$HOME/.config/zsh"'
  home_file .config/zsh/.zshrc 'alias ll="ls -l"'
  install
  run "${SANDBOX}/home/.local/share/om818/bin/om818" uninstall
  assert_status 0
  assert_output_not_contains 'zsh reads ~/.zshrc again'
  assert_file_contains .zshenv 'export ZDOTDIR="$HOME/.config/zsh"'
  assert_file_contains .config/zsh/.zshrc 'alias ll="ls -l"'
}

# A ZDOTDIR= in a comment of ~/.zshenv sets nothing: the om818 line is still added
function test_commented_zdotdir() {
  home_file .zshenv '# ZDOTDIR=~/old (kept for later)'
  install
  assert_file_contains .zshenv 'export ZDOTDIR='
}

# A failed temporary setup without XDG_RUNTIME_DIR: the ~/.cache it made goes with its folder
function test_temp_failed_setup_leaves_no_cache() {
  tty_available || return 0
  run tmux -S "$TMUX_SOCKET" -f /dev/null -u new-session -d -x 100 -y 30 \
    "env OM818_REPO=${SANDBOX}/none sh ${FIXTURE}/install.sh --temp; echo status=\$?; sleep 30"
  if ! wait_for tty_has '^status=1$'; then fail "no status: $(tty_read && echo "$OUTPUT")"; fi
  if [[ -e "${SANDBOX}/home/.cache" ]]; then fail "left: $(ls -A -- "${SANDBOX}/home/.cache")"; fi
}

# A temporary session on an account with oh-my-818: its commands go to the history its shells read
function test_temp_history_of_an_installed_account() {
  local run="${SANDBOX}/run" shell file login
  tty_available || return 0
  install
  mkdir -m 700 -- "$run"
  for shell in zsh bash; do
    file="${SANDBOX}/home/.local/state/${shell}/history"
    mkdir -p -- "${file%/*}"
    : >"$file"
    login=/bin/zsh
    if [[ "$shell" == bash ]]; then login="${SANDBOX}/bin/bash"; fi
    tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${login} sh ${FIXTURE}/install.sh --temp"
    tty_type "echo temp-${shell}"
    # (status there: the login shell is the install's wrapper in bash, not shown as such)
    tty_type "om818 status >${SANDBOX}/status-${shell} 2>&1"
    if ! wait_for grep -qs "temp-${shell}" "$file"; then
      fail "${shell}: not in ~/.local/state/${shell}/history: $(ls -A -- "${SANDBOX}/home")"
    fi
    # (to its end, in both shells: closing the terminal during it could leave its probe's shell)
    if ! wait_for grep -qsE 'All good|to fix \(marked' "${SANDBOX}/status-${shell}"; then
      fail "${shell}, no status: $(cat -- "${SANDBOX}/status-${shell}" 2>/dev/null)"
    fi
    if [[ "$shell" == bash ]] && ! grep -qs "login shell: the temporary install's" \
      "${SANDBOX}/status-${shell}"; then
      fail "status: $(cat -- "${SANDBOX}/status-${shell}" 2>/dev/null)"
    fi
    run tmux -S "$TMUX_SOCKET" kill-server
    if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail "${shell}: left"; fi
  done
  # Uninstalled, its history files left: the files the account's shells read again
  rm -rf -- "${SANDBOX}/home/.local/share/om818"
  for shell in zsh bash; do
    login=/bin/zsh
    if [[ "$shell" == bash ]]; then login="${SANDBOX}/bin/bash"; fi
    tty_start "env XDG_RUNTIME_DIR=${run} SHELL=${login} sh ${FIXTURE}/install.sh --temp"
    tty_type "echo after-${shell}"
    if ! wait_for grep -qs "after-${shell}" "${SANDBOX}/home/.${shell}_history"; then
      fail "${shell}, after an uninstall: not in ~/.${shell}_history"
    fi
    run tmux -S "$TMUX_SOCKET" kill-server
    if ! wait_for eval '[[ ! -e "${run}/om818-temp${TEMP_NS}" ]]'; then fail "${shell}: left"; fi
  done
}

# In a temporary session: the exit hook removes the folder it registered in, whatever the variable
# says by then; status doesn't show the host's name (in the folder's)
function test_temp_exit_and_status_keep_to_the_folder() {
  local folder
  tty_available || return 0
  folder="${SANDBOX}/home/.cache/om818-temp-$(uname -n | tr -c 'A-Za-z0-9._\n-' _)${TEMP_NS}"
  mkdir -p -- "${SANDBOX}/home/victim"
  tty_start "env XDG_RUNTIME_DIR=${SANDBOX}/none sh ${FIXTURE}/install.sh --temp"
  # (and before the system's zshrc, Ubuntu's skipping its compinit: set from .zshenv)
  tty_type "zsh -c 'print -r -- \${skip_global_compinit:-unset}' >${SANDBOX}/skip"
  # (bash typed in it: the temporary install's too)
  tty_type "bash -ic 'printf %s \"\${OM818_DIR:-}\"' >${SANDBOX}/nested 2>/dev/null"
  tty_type "om818 status >${SANDBOX}/status 2>&1"
  if ! wait_for test -s "${SANDBOX}/status"; then fail 'no status'; fi
  if [[ "$(<"${SANDBOX}/skip")" != 1 ]]; then fail "skip_global_compinit: $(<"${SANDBOX}/skip")"; fi
  # (-ef: the folder's path resolved, as macOS's /var is /private/var)
  if ! [[ "$(<"${SANDBOX}/nested")" -ef "${folder}/om818" ]]; then
    fail "bash typed in it: $(<"${SANDBOX}/nested")"
  fi
  # (else the checks below would pass for any folder)
  if [[ ! -d "$folder" ]]; then fail "not in ${folder}: $(ls -A -- "${SANDBOX}/home/.cache")"; fi
  if grep -q -- "$(uname -n)" "${SANDBOX}/status"; then
    fail "host shown: $(<"${SANDBOX}/status")"
  fi
  tty_type 'OM818_TEMP=~/victim; exit'
  if ! wait_for eval '[[ ! -e "$folder" ]]'; then fail 'its folder left'; fi
  if [[ ! -d "${SANDBOX}/home/victim" ]]; then fail 'another folder removed'; fi
}

# A shell started in another PID namespace inside a session (bwrap, unshare): it can't see the
# session's shells, so it leaves the folder alone when it exits
function test_temp_shell_in_another_pid_namespace() {
  local run="${SANDBOX}/run" unshare
  tty_available || return 0
  unshare="$(command -v unshare)" || return 0
  "$unshare" --pid --fork --user --map-current-user true 2>/dev/null || return 0
  mkdir -m 700 -- "$run"
  tty_start "env XDG_RUNTIME_DIR=${run} SHELL=/bin/zsh sh ${FIXTURE}/install.sh --temp"
  tty_type "${unshare} --pid --fork --user --map-current-user zsh -i -c exit; : >${SANDBOX}/done"
  if ! wait_for test -e "${SANDBOX}/done"; then fail 'the nested shell never ended'; fi
  if [[ ! -d "${run}/om818-temp${TEMP_NS}" ]]; then fail 'the live folder removed'; fi
  run tmux -S "$TMUX_SOCKET" kill-server
}

# A setgid cache folder (its folders inherit the bit): the temporary install's made private anyway
function test_temp_in_a_setgid_folder() {
  tty_available || return 0
  mkdir -m 700 -- "${SANDBOX}/cache"
  chmod g+s "${SANDBOX}/cache"
  tty_start "env XDG_RUNTIME_DIR=${SANDBOX}/none XDG_CACHE_HOME=${SANDBOX}/cache \
    sh ${FIXTURE}/install.sh --temp"
  if ! compgen -G "${SANDBOX}/cache/om818-temp-*" >/dev/null; then fail 'not used'; fi
}

run_tests "$@"
