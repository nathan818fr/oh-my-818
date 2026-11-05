# shellcheck shell=sh
# The shell startup files (POSIX sh, sourced by bin/om818 after lib/common.sh): each gets the lines
# it needs, marked "# om818", unless it already loads oh-my-818 (e.g. managed by a dotfiles tool).

# The lines, with paths that also work in a sandbox with another HOME. The environment is loaded
# once per shell: ~/.profile often sources ~/.bashrc, which loads it too (om818_path_prepend comes
# from env.sh: defined means loaded)
# shellcheck disable=SC2016
_OM818_STARTUP_ENV_FILE='"${XDG_STATE_HOME:-$HOME/.local/state}/om818/env.sh"'
_OM818_STARTUP_ENV_LINE="if [ -r ${_OM818_STARTUP_ENV_FILE} ] &&"
_OM818_STARTUP_ENV_LINE="${_OM818_STARTUP_ENV_LINE} ! command -v om818_path_prepend"
_OM818_STARTUP_ENV_LINE="${_OM818_STARTUP_ENV_LINE} >/dev/null 2>&1;"
_OM818_STARTUP_ENV_LINE="${_OM818_STARTUP_ENV_LINE} then . ${_OM818_STARTUP_ENV_FILE}; fi # om818"
# Only once the folder has its .zshrc: a ~/.zshenv shared by dotfiles with a machine without
# oh-my-818 (or whose install failed) must not send zsh to an empty folder
# shellcheck disable=SC2016
_OM818_STARTUP_ZDOTDIR_LINE='if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/.zshrc" ]; then'
_OM818_STARTUP_ZDOTDIR_LINE="${_OM818_STARTUP_ZDOTDIR_LINE}"' export ZDOTDIR="${XDG_CONFIG_HOME:-'
_OM818_STARTUP_ZDOTDIR_LINE="${_OM818_STARTUP_ZDOTDIR_LINE}"'$HOME/.config}/zsh"; fi # om818'
# bash only (any sh reads ~/.profile), and only when interactive ("${-#*i}" != "$-": $- has i)
# shellcheck disable=SC2016
_OM818_STARTUP_BASHRC_LINE='if [ -n "${BASH_VERSION:-}" ] && [ "${-#*i}" != "$-" ] &&'
_OM818_STARTUP_BASHRC_LINE="${_OM818_STARTUP_BASHRC_LINE}"' [ -r "$HOME/.bashrc" ];'
_OM818_STARTUP_BASHRC_LINE="${_OM818_STARTUP_BASHRC_LINE}"' then . "$HOME/.bashrc"; fi # om818'

# zsh's ZDOTDIR as zsh sees it (find_zdotdir)
_OM818_ZSH_ZDOTDIR=''
# The files oh-my-818 had made read-only, before release_startup_files
_OM818_PROTECTED_BEFORE=''
# zsh's files in HOME it no longer reads, holding something (zsh_ignored_files)
_OM818_ZSH_IGNORED=''
# 1 once startup_info printed its header
_OM818_STARTUP_HEADER=0
# 1 when a line couldn't be added (read-only file): the user adds it
_OM818_STARTUP_TODO=0

# Set _OM818_ZSH_ZDOTDIR to zsh's ZDOTDIR as zsh sees it (after ~/.zshenv), empty when nothing
# sets it
find_zdotdir() {
  # An inherited ZDOTDIR of oh-my-818's own path is left out: the session may come from an
  # install since removed (a reinstall before logging out). So is one set to HOME: VS Code's
  # terminal exports it. zsh tells whether they are still set
  # shellcheck disable=SC2016
  if [ -n "${ZDOTDIR:-}" ] && [ "$ZDOTDIR" != "$HOME" ] &&
    [ "$ZDOTDIR" != "${XDG_CONFIG_HOME:-${HOME}/.config}/zsh" ]; then
    _OM818_ZSH_ZDOTDIR="$ZDOTDIR"
  elif command -v zsh >/dev/null 2>&1; then
    # (also without ~/.zshenv: the system's zshenv may set it)
    _OM818_ZSH_ZDOTDIR="$(unset ZDOTDIR && zsh -c 'printf "%s\n" "${ZDOTDIR:-}"' 2>/dev/null ||
      true)"
  else
    _OM818_ZSH_ZDOTDIR=''
  fi
}

# Print the directory of zsh's startup files: zsh's ZDOTDIR, else ~/.config/zsh (where the line
# oh-my-818 adds to ~/.zshenv points)
zdotdir() {
  printf '%s\n' "${_OM818_ZSH_ZDOTDIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/zsh}"
}

# Print the startup files of <shell> that set HISTFILE (ZDOTDIR's too: zsh reads them until
# logging out); status 1 when there is none
# usage: history_own_files zsh|bash
history_own_files() {
  local zdir files
  # (grep's status: 2 when a file is missing, even with a match)
  if [ "$1" = zsh ]; then
    zdir="$(zdotdir)"
    files="$(grep -ls 'HISTFILE=' -- "${HOME}/.zshrc" "${HOME}/.zshenv" "${HOME}/.zprofile" \
      "${HOME}/.zlogin" "${zdir}/.zshenv" "${zdir}/.zshrc" "${zdir}/.zprofile" \
      "${zdir}/.zlogin" 2>/dev/null)" || true
  else
    files="$(grep -ls 'HISTFILE=' -- "${HOME}/.bashrc" "${HOME}/.bash_profile" \
      "${HOME}/.bash_login" "${HOME}/.profile" 2>/dev/null)" || true
  fi
  if [ -z "$files" ]; then return 1; fi
  printf '%s\n' "$files"
}

# Whether a shell's interactive startup loads oh-my-818, from its rc file or through a file it
# sources: when the rc file doesn't name it, the shell is started to see. That shell runs the
# user's whole rc file, without oh-my-818's update check or env.sh regeneration (OM818_PROBE=1),
# OM818_DIR emptied (only the rc file
# can set it), and when possible, no terminal (setsid: a password prompt fails instead of asking)
# and a time limit
# usage: shell_loads_om818 zsh|bash
shell_loads_om818() {
  local file
  if [ "$1" = 'zsh' ]; then file="$(zdotdir)/.zshrc"; else file="${HOME}/.bashrc"; fi
  if grep -qsF "om818.plugin.${1}" "$file"; then return 0; fi
  if [ ! -e "$file" ] || ! command -v "$1" >/dev/null 2>&1; then return 1; fi
  # shellcheck disable=SC2016 # its code
  shell_probe "$1" '[ -n "${OM818_DIR:-}" ]'
}

# Run code in an interactive shell started as a terminal's (the user's whole rc file, without
# oh-my-818's update check or env.sh regeneration: OM818_PROBE), with a time limit; its status
# usage: shell_probe zsh|bash <code>
shell_probe() {
  local wrap=''
  # The time limit only with a session of its own (setsid -w waits for the shell: util-linux's has
  # it, busybox's doesn't): an interactive shell under timeout alone stops on SIGTTIN, waiting for
  # the terminal, and it ignores SIGTERM (hence KILL)
  if setsid -w true >/dev/null 2>&1; then
    wrap='setsid -w'
    if command -v timeout >/dev/null 2>&1; then wrap="timeout -s KILL 10 ${wrap}"; fi
  fi
  # (not OM818_LOCKED: a daemon the rc file starts would keep it, and its shells skip the lock)
  # shellcheck disable=SC2086 # $wrap: words
  (
    unset OM818_LOCKED
    OM818_PROBE=1 OM818_DIR='' $wrap "$1" -i -c "$2" </dev/null >/dev/null 2>&1
  )
}

# Print the line that loads a shell's module. At the default location, a line without its path
# (it works in a sandbox with another HOME); elsewhere, the absolute path
# usage: plugin_line zsh|bash
plugin_line() {
  local default="${XDG_DATA_HOME:-${HOME}/.local/share}/om818" file
  # shellcheck disable=SC2016
  if same_dir "$OM818_DIR" "$default"; then
    file='"${XDG_DATA_HOME:-$HOME/.local/share}/om818/om818.plugin.'"$1"'"'
  else
    file="$(quote "${OM818_DIR}/om818.plugin.${1}")"
  fi
  printf 'if [ -r %s ]; then source %s; fi # om818\n' "$file" "$file"
}

# Whether two paths are the same directory (one may go through a symlink, e.g. macOS's /var)
same_dir() {
  if [ "$1" = "$2" ]; then return 0; fi
  [ -d "$1" ] && [ -d "$2" ] && [ "$(cd -- "$1" && pwd -P)" = "$(cd -- "$2" && pwd -P)" ]
}

# Whether the login shell is bash (SHELL may be unset: containers, Dockerfile RUN lines)
login_shell_is_bash() {
  case "${SHELL:-}" in bash | */bash) return 0 ;; *) return 1 ;; esac
}

# Print the bash login file bash reads instead of ~/.profile, if any
bash_login_file() {
  local file
  for file in "${HOME}/.bash_profile" "${HOME}/.bash_login"; do
    if [ -e "$file" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done
}

# Print zsh's files in HOME that zsh no longer reads once ZDOTDIR moves them, those holding
# something (a distribution's untouched default, from /etc/skel, aside)
zsh_ignored_files() {
  local zdir file
  zdir="$(zdotdir)"
  if [ "$zdir" = "$HOME" ]; then return 0; fi
  for file in .zshrc .zprofile .zlogin .zlogout; do
    if [ ! -s "${HOME}/${file}" ] || [ ! -w "${HOME}/${file}" ]; then continue; fi
    if cmp -s -- "${HOME}/${file}" "/etc/skel/${file}"; then continue; fi
    printf '%s\n' "${HOME}/${file}"
  done
}

# Add the lines oh-my-818 needs to the startup files
# usage: wire_startup_files <quiet: 0 or 1>
wire_startup_files() {
  local zdir login file list=''
  if command -v zsh >/dev/null 2>&1; then find_zdotdir; fi
  release_startup_files
  if command -v zsh >/dev/null 2>&1; then
    # ZDOTDIR: kept when something already sets it, else ~/.config/zsh. Set to ~/.config/zsh
    # already, the line is added too: Alpine's /etc/zsh/zshenv sets it only while the home has no
    # zsh file, and the ~/.zshenv made below would stop it
    if [ -z "$_OM818_ZSH_ZDOTDIR" ] ||
      [ "$_OM818_ZSH_ZDOTDIR" = "${XDG_CONFIG_HOME:-${HOME}/.config}/zsh" ]; then
      # (the line itself: a ZDOTDIR= in a comment sets nothing, zsh said so above)
      wire_line "${HOME}/.zshenv" "$_OM818_STARTUP_ZDOTDIR_LINE" "$_OM818_STARTUP_ZDOTDIR_LINE" \
        "sets ZDOTDIR (zsh's files in ~/.config/zsh)" create
    fi
    zdir="$(zdotdir)"
    wire_line "${HOME}/.zshenv" 'om818/env.sh' "$_OM818_STARTUP_ENV_LINE" \
      'loads the environment' create
    if ! shell_loads_om818 zsh; then
      wire_line "${zdir}/.zshrc" 'om818.plugin.zsh' "$(plugin_line zsh)" 'loads oh-my-818' create
    fi
    # (bin/om818 warns about them last; the first zsh says it again: modules/zsh/init.zsh)
    # shellcheck disable=SC2034 # read by bin/om818
    _OM818_ZSH_IGNORED="$(zsh_ignored_files)"
  fi

  wire_line "${HOME}/.profile" 'om818/env.sh' "$_OM818_STARTUP_ENV_LINE" \
    'loads the environment' create
  login="$(bash_login_file)"
  if [ -n "$login" ]; then
    wire_line "$login" 'om818/env.sh' "$_OM818_STARTUP_ENV_LINE" 'loads the environment'
  fi
  # ~/.bashrc: when bash 4.4+ is installed (also when it isn't the login shell: typing `bash`), or
  # it exists, or bash is the login shell. The environment line goes first: Debian's and Ubuntu's
  # .bashrc stop early in non-interactive shells (`ssh host cmd`)
  if [ -e "${HOME}/.bashrc" ] || login_shell_is_bash || bash_supported; then
    if ! shell_loads_om818 bash; then
      wire_line "${HOME}/.bashrc" 'om818/env.sh' "$_OM818_STARTUP_ENV_LINE" \
        'loads the environment' 'create top'
      wire_line "${HOME}/.bashrc" 'om818.plugin.bash' "$(plugin_line bash)" 'loads oh-my-818' \
        create
    fi
  fi
  # When bash is the login shell (terminals on macOS, ssh), it reads its login file, not ~/.bashrc:
  # unless that file already does (most distros' do), it reads ~/.bashrc when interactive
  if login_shell_is_bash; then
    wire_line "${login:-${HOME}/.profile}" '.bashrc' "$_OM818_STARTUP_BASHRC_LINE" \
      'loads ~/.bashrc in interactive login shells'
  fi
  if [ "$(setting om818_protect_startup_files)" = 'on' ]; then
    protect_startup_files
  else
    while IFS= read -r file; do
      if [ -e "$file" ]; then list="${list:+${list}, }$(tilde "$file")"; fi
    done <<EOF
$_OM818_PROTECTED_BEFORE
EOF
    if [ -n "$list" ]; then
      startup_info "writable again (om818_protect_startup_files=off): ${list}"
    fi
  fi
}

# Print a line about the startup files, after a header the first time
startup_info() {
  if [ "$_OM818_STARTUP_HEADER" -eq 0 ]; then
    info 'Startup files (lines marked # om818):'
    _OM818_STARTUP_HEADER=1
  fi
  info "  $*"
}

# Print the startup files oh-my-818 wires, those that exist
startup_files() {
  local file
  if command -v zsh >/dev/null 2>&1; then
    printf '%s\n' "${HOME}/.zshenv" "$(zdotdir)/.zshrc"
  elif [ -e "${HOME}/.zshenv" ]; then
    # (zsh removed since: its file may still hold the lines)
    printf '%s\n' "${HOME}/.zshenv"
  fi
  for file in .profile .bash_profile .bash_login .bashrc; do
    if [ -e "${HOME}/${file}" ]; then printf '%s\n' "${HOME}/${file}"; fi
  done
}

# Print the zsh files oh-my-818 doesn't wire, which an installer could create or add lines to:
# those zsh reads (.zprofile, .zlogin, and .zshenv when ZDOTDIR moved zsh's files: an exported
# ZDOTDIR makes zsh read it), and ~/.zshrc, which installers ignoring ZDOTDIR write to
startup_guards() {
  local zdir
  if ! command -v zsh >/dev/null 2>&1; then return 0; fi
  zdir="$(zdotdir)"
  if [ "$zdir" != "$HOME" ]; then printf '%s\n' "${HOME}/.zshrc" "${zdir}/.zshenv"; fi
  printf '%s\n' "${zdir}/.zprofile" "${zdir}/.zlogin"
}

# Make the startup files read-only (om818_protect_startup_files=on): installers can't add lines
# to them unseen (they fail instead). The guards (startup_guards) missing are created empty, so
# that installers can't create them either. Only the writable files change, and are listed (state
# folder: protected, "<guard or file><tab><group/other write bits: g, o><tab><path>" per line), so
# that turning the setting off restores just those as they were, never a file the user protected
protect_startup_files() {
  local file list="${OM818_STATE_DIR}/protected" made='' created='' kind bits mode
  mkdir -p -- "$OM818_STATE_DIR"
  while IFS= read -r file; do
    if [ ! -e "$file" ]; then
      mkdir -p -- "$(dirname -- "$file")"
      : >"$file"
      created="${created}${file}
"
    fi
  done <<EOF
$(startup_guards)
EOF
  while IFS= read -r file; do
    if [ ! -e "$file" ] || [ ! -w "$file" ]; then continue; fi
    kind='file'
    case "
${created}" in *"
${file}
"*) kind=guard ;; esac
    # ls -l's mode: -rw-rw-r--, the group's w 6th, the others' 9th (-L: a link's target, whose
    # mode chmod changes; a link's own is always rwxrwxrwx)
    mode="$(ls -ldL -- "$file")"
    bits=''
    case "$mode" in ?????w*) bits=g ;; esac
    case "$mode" in ????????w*) bits="${bits}o" ;; esac
    # (listed first: if the chmod is interrupted, the next install still knows the file)
    printf '%s\t%s\t%s\n' "$kind" "${bits:--}" "$file" >>"$list"
    chmod a-w "$file"
    case "
${_OM818_PROTECTED_BEFORE}
" in
    *"
${file}
"*) ;;
    *) made="${made:+${made}, }$(tilde "$file")" ;;
    esac
  done <<EOF
$(startup_files)
$(startup_guards)
EOF
  if [ -n "$made" ]; then
    startup_info "made read-only (om818_protect_startup_files=on): ${made}"
  fi
}

# Make the files oh-my-818 made read-only writable again, so that it can add a line they miss
# (protect_startup_files protects them again), and remove the empty guards it created. The list
# goes to _OM818_PROTECTED_BEFORE
release_startup_files() {
  local file list="${OM818_STATE_DIR}/protected" kind bits
  _OM818_PROTECTED_BEFORE=''
  if [ ! -f "$list" ]; then return 0; fi
  while IFS='	' read -r kind bits file; do
    # (a list from an earlier version: a path alone per line)
    if [ -z "$bits" ] && [ -z "$file" ]; then
      file="$kind"
      kind='file'
    fi
    if [ -z "$file" ] || [ ! -e "$file" ]; then continue; fi
    _OM818_PROTECTED_BEFORE="${_OM818_PROTECTED_BEFORE}${file}
"
    chmod u+w "$file"
    case "$bits" in *g*) chmod g+w "$file" ;; esac
    case "$bits" in *o*) chmod o+w "$file" ;; esac
    # (a guard it created, still empty)
    if [ "$kind" = guard ] && [ ! -s "$file" ]; then rm -f -- "$file"; fi
  done <"$list"
  rm -f -- "$list"
}

# Add a line to a file (at its end; "top": first), unless the file already has the pattern;
# "create": also when the file doesn't exist. A read-only file is left as is: its line is shown
# usage: wire_line <file> <pattern> <line> <what it does> [create] [top]
wire_line() {
  local file="$1" pattern="$2" line="$3" what="$4" flags=" ${5:-} " tmp
  if [ -e "$file" ] && grep -qsF "$pattern" "$file"; then return 0; fi
  if [ ! -e "$file" ] && [ "$flags" = "${flags#* create }" ]; then return 0; fi
  # A read-only file is protected on purpose (e.g. from installers that append to it)
  if [ -e "$file" ] && [ ! -w "$file" ]; then
    # shellcheck disable=SC2034 # read by bin/om818
    _OM818_STARTUP_TODO=1
    info "warning: $(tilde "$file") is read-only: add this line yourself (it ${what}), or make"
    info "  it writable (chmod u+w) and run $(tilde "${OM818_DIR}/bin/om818") install:"
    info "  ${line}"
    return 0
  fi
  if [ ! -e "$file" ]; then
    mkdir -p -- "$(dirname -- "$file")"
    if ! printf '%s\n' "$line" >"$file"; then
      wire_failed "$file" "$line" "$what"
      return 0
    fi
    startup_info "$(tilde "$file"): created, with a line that ${what}"
    return 0
  fi
  if [ "$flags" != "${flags#* top }" ] && [ -s "$file" ]; then
    # Through a temporary file, then written into the file itself: it keeps its owner, mode and
    # links (e.g. a symlink into a dotfiles repo)
    tmp="${OM818_STATE_DIR}/startup.tmp.$$"
    mkdir -p -- "$OM818_STATE_DIR"
    # (private: it holds the file's content)
    if ! (umask 077 && { printf '%s\n' "$line" && cat -- "$file"; } >"$tmp"); then
      rm -f -- "$tmp"
      wire_failed "$file" "$line" "$what"
      return 0
    fi
    if ! cat -- "$tmp" >"$file"; then
      # It may be cut short (e.g. a full disk): the full copy is kept in HOME, out of the state
      # folder, which uninstall removes
      mv -f -- "$tmp" "${HOME}/.om818-${file##*/}" 2>/dev/null && tmp="${HOME}/.om818-${file##*/}"
      # shellcheck disable=SC2034 # read by bin/om818
      _OM818_STARTUP_TODO=1
      info "warning: cannot rewrite $(tilde "$file"), which may be cut short: its content, with"
      info "  oh-my-818's line first, is in $(tilde "$tmp")"
      return 0
    fi
    rm -f -- "$tmp"
  else
    # A last line without its newline gets one first ($(…) drops a final newline: empty means
    # the file ends with one)
    if [ -s "$file" ] && [ "$(tail -c 1 -- "$file")" != '' ] &&
      ! { printf '\n' >>"$file"; } 2>/dev/null; then
      wire_failed "$file" "$line" "$what"
      return 0
    fi
    if ! printf '%s\n' "$line" >>"$file"; then
      wire_failed "$file" "$line" "$what"
      return 0
    fi
  fi
  startup_info "$(tilde "$file"): added a line that ${what}"
}

wire_failed() {
  # shellcheck disable=SC2034 # read by bin/om818
  _OM818_STARTUP_TODO=1
  info "warning: cannot write $(tilde "$1"): add this line yourself (it ${3}):"
  info "  ${2}"
}

# Print the state of a startup file: ok, missing (no line) or absent (no file)
startup_state() {
  if [ ! -e "$1" ]; then
    printf 'absent\n'
  elif grep -qsF "$2" "$1"; then
    printf 'ok\n'
  else
    printf 'missing\n'
  fi
}
