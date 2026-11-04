# shellcheck shell=sh
# Shared by bin/om818 (POSIX sh, sourced): paths, messages, config and versions.

# Where things live (XDG base dirs, with the spec's defaults)
# shellcheck disable=SC2034
OM818_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/om818"
OM818_STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/om818"
OM818_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/om818"
# A temporary install (install.sh --temp): all in its folder, if it is one of the user's (as the
# shells check it: not another user's, e.g. through sudo keeping the variable)
# shellcheck disable=SC2012,SC2046
case "${OM818_TEMP:-}" in
/*)
  if [ -L "$OM818_TEMP" ] || [ ! -d "$OM818_TEMP" ] ||
    [ "$(set -f && set -- $(ls -ldn -- "$OM818_TEMP") && echo "$3")" != "$(id -u)" ]; then
    unset OM818_TEMP
  fi
  ;;
*) unset OM818_TEMP ;;
esac
if [ -n "${OM818_TEMP:-}" ]; then
  OM818_CONFIG_DIR="${OM818_TEMP}/config"
  OM818_STATE_DIR="${OM818_TEMP}/state"
  OM818_CACHE_DIR="${OM818_TEMP}/cache"
fi
OM818_CONFIG="${OM818_CONFIG_DIR}/config.sh"
OM818_ENV_D="${OM818_CONFIG_DIR}/env.d"
OM818_SHELL_D="${OM818_CONFIG_DIR}/shell.d"
OM818_ENV="${OM818_STATE_DIR}/env.sh"

# Internal globals start with _OM818_: no clash with a variable of the environment or a tool
_OM818_EXIT_TMP=''        # a temporary file removed on exit (env_generate)
_OM818_OWNS_LOCK_FOLDER=0 # 1 while this process holds the lock folder (lock_folder_try)
_OM818_LOCK_OWNER=''      # its "owner" line (pid, host when taken: the host name may change)
_OM818_DOWNLOAD_PID=''    # the gitstatusd download running (gitstatusd_download), stopped on exit
_OM818_ARGS=''            # om818's arguments, quoted: lock_take runs it again with them
_OM818_CMD=''             # om818's command (install, status…), for messages

# The EXIT trap (bin/om818 sets it): the temporary file, the download, the lock
on_exit() {
  local owner
  # (a second signal, e.g. the terminal's HUP after Ctrl+C, would stop the cleanup)
  trap '' HUP INT TERM
  if [ -n "$_OM818_EXIT_TMP" ]; then rm -f -- "$_OM818_EXIT_TMP"; fi
  if [ -n "$_OM818_DOWNLOAD_PID" ]; then kill "$_OM818_DOWNLOAD_PID" 2>/dev/null || true; fi
  # (unless taken over meanwhile: then another's)
  if [ "$_OM818_OWNS_LOCK_FOLDER" -eq 1 ]; then
    owner="$(cut -d ' ' -f 1,2 -- "${OM818_STATE_DIR}/lock.d/owner" 2>/dev/null)" || owner=''
    if [ "$owner" = "$_OM818_LOCK_OWNER" ]; then rm -rf -- "${OM818_STATE_DIR}/lock.d"; fi
  fi
}

# One install, update, rollback, uninstall or env at a time: flock on "lock" where it exists
# (released when the process ends), else the folder "lock.d" (lock_folder_try). The command then
# runs again in a child, without the lock's fd (OM818_LOCKED): a daemon it starts (git gc, the
# user's startup files) can't keep the lock. Status 1: busy (at once with quiet, else after 30 s);
# 2: can't write the state folder
# usage: lock_take [quiet]
lock_take() {
  local tries=0 status lock="${OM818_STATE_DIR}/lock" flock=0
  if [ -n "${OM818_LOCKED:-}" ]; then return 0; fi
  mkdir -p -- "$OM818_STATE_DIR" 2>/dev/null || return 2
  # (-w: also false on a read-only mount)
  if [ ! -w "$OM818_STATE_DIR" ]; then return 2; fi
  if command -v flock >/dev/null 2>&1; then
    # Private: another user able to open it could hold it. (In a subshell: a failed redirection of
    # a special builtin, such as exec, would exit the shell)
    (umask 077 && : >>"$lock") 2>/dev/null || return 2
    exec 9>>"$lock"
    flock=1
  fi
  while :; do
    status=0
    if [ "$flock" -eq 1 ]; then
      flock -n 9 2>/dev/null || status=$?
      # (another status than "busy" is an error: the lock folder instead)
      if [ "$status" -gt 1 ]; then
        exec 9>&-
        flock=0
        continue
      fi
    else
      lock_folder_try || status=$?
    fi
    if [ "$status" -eq 0 ]; then break; fi
    if [ "$status" -eq 2 ]; then return 2; fi
    tries=$((tries + 1))
    if [ "${1:-}" = quiet ] || [ "$tries" -gt 30 ]; then return 1; fi
    sleep 1
  done
  OM818_LOCKED=1
  export OM818_LOCKED
  # (its status passed on explicitly: callers test lock_take, which turns errexit off here)
  status=0
  eval "\"\${OM818_DIR}/bin/om818\" ${_OM818_ARGS}" 9>&- || status=$?
  exit "$status"
}

# One try at the lock folder: 0 when taken, 1 when another holds it, 2 when it can't be made. Its
# file "owner" holds the owner's pid, host and start time. A lock whose owner is gone (killed, its
# terminal closed), or 10 minutes old (its pid reused after a reboot, an owner on another host),
# is taken over, through a rename only one process wins
lock_folder_try() {
  local lock="${OM818_STATE_DIR}/lock.d"
  if mkdir -- "$lock" 2>/dev/null; then
    _OM818_OWNS_LOCK_FOLDER=1
    # (the host name as one word: it may hold blanks)
    _OM818_LOCK_OWNER="$$ $(uname -n | tr -c 'A-Za-z0-9._\n-' _)"
    # (its owner unwritten, e.g. a full disk: not left to block the next commands)
    if ! (printf '%s %s\n' "$_OM818_LOCK_OWNER" "$(date +%s)" >"${lock}/owner") 2>/dev/null; then
      rm -rf -- "$lock"
      _OM818_OWNS_LOCK_FOLDER=0
      return 2
    fi
    return 0
  fi
  if [ ! -d "$lock" ]; then
    # (a file of that name: not a lock of this code's)
    if [ -e "$lock" ] && rm -f -- "$lock"; then return 1; fi
    return 2
  fi
  if lock_folder_alive "$lock"; then return 1; fi
  if mv -- "$lock" "${lock}.stale.$$" 2>/dev/null; then
    # (another process may have taken it over meanwhile: then it is theirs, given back)
    if lock_folder_alive "${lock}.stale.$$"; then
      mv -- "${lock}.stale.$$" "$lock" 2>/dev/null || rm -rf -- "${lock}.stale.$$"
    else
      rm -rf -- "${lock}.stale.$$"
      lock_folder_try
      return
    fi
  fi
  return 1
}

# Whether a lock folder's owner may still run: younger than 10 minutes, and its process alive, on
# another host (can't be checked), or not written yet (just made)
lock_folder_alive() {
  local pid='' host='' since=''
  { read -r pid host since <"${1}/owner"; } 2>/dev/null || true
  case "$since" in '' | *[!0-9]*) since='' ;; esac
  # (no start time: the folder's, through `find` where it exists)
  if [ -n "$since" ]; then
    if [ "$(($(date +%s) - since))" -gt 600 ]; then return 1; fi
  elif [ -n "$(find "$1" -prune -mmin +10 2>/dev/null)" ]; then
    return 1
  fi
  if [ -z "$pid" ] || [ "$host" != "$(uname -n | tr -c 'A-Za-z0-9._\n-' _)" ]; then return 0; fi
  kill -0 "$pid" 2>/dev/null
}

info() {
  printf '%s\n' "$*" >&2
}

# Print a shell's history file: in XDG's state folder, where the Arch wiki's XDG page puts it
# usage: history_file zsh|bash
history_file() {
  printf '%s/%s/history\n' "${XDG_STATE_HOME:-${HOME}/.local/state}" "$1"
}

# Print a path with ~ for the home directory (messages)
# shellcheck disable=SC2088 # a ~ to show
tilde() {
  case "$1" in
  "$HOME") printf '~\n' ;;
  "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
  *) printf '%s\n' "$1" ;;
  esac
}

# Print a text with ~ for the home directory, wherever it is in it
# shellcheck disable=SC2088 # a ~ to show
tilde_text() {
  text_replace "$1" "${HOME}/" '~/'
}

# Print a text with each <from> replaced by <to>
# usage: text_replace <text> <from> <to>
text_replace() {
  local rest="$1" out=''
  while [ -n "$2" ]; do
    case "$rest" in
    *"$2"*)
      out="${out}${rest%%"$2"*}${3}"
      rest="${rest#*"$2"}"
      ;;
    *) break ;;
    esac
  done
  printf '%s\n' "${out}${rest}"
}

error() {
  printf 'error: %s\n' "$*" >&2
}

# Load the scalar settings (defaults.sh, then the user's config) into this shell. They may use
# arrays (for the shells' modules), so a shell that has them reads them and prints name=value lines
config_load() {
  local out line name
  if ! out="$(config_dump)"; then
    error "$(tilde "$OM818_CONFIG") has an error (see above): fix it, or move it away"
    return 1
  fi
  while [ -n "$out" ]; do
    line="${out%%"
"*}"
    if [ "$line" = "$out" ]; then out=''; else out="${out#*"
"}"; fi
    name="${line%%=*}"
    case "$name" in
    om818_*) ;;
    *) continue ;;
    esac
    case "$name" in
    *[!a-z0-9_]*) continue ;;
    esac
    # (eval only assigns: the value is expanded, not parsed again, so any text is safe; the name
    # was checked above)
    eval "${name}=\${line#*=}"
  done
}

# Load the defaults alone (when the user's config has an error)
config_defaults() {
  local config="$OM818_CONFIG"
  OM818_CONFIG='/dev/null/none'
  config_load
  OM818_CONFIG="$config"
}

# Print the problems of the user's config in one line (nothing when there are none): unknown
# settings (assigned anywhere, also in conditions; not in defaults.sh) and invalid values of
# on/off/auto settings (from their default's kind)
config_problems() {
  local names name unknown='' invalid='' defaults default value
  if [ ! -r "$OM818_CONFIG" ]; then return 0; fi
  names="$(grep -o 'om818_[a-z0-9_]*\(\[[^]]*\]\)\{0,1\}+\{0,1\}=' "$OM818_CONFIG" |
    sed 's/[[+=].*//' | sort -u)"
  defaults="$(sed -nE 's/^(typeset -gA )?(om818_[a-z0-9_]+)=([a-z]*).*/\2 \3/p' \
    "${OM818_DIR}/defaults.sh")"
  for name in $names; do
    if ! printf '%s\n' "$defaults" | grep -q "^${name} "; then
      unknown="${unknown} ${name}"
      continue
    fi
    default="$(printf '%s\n' "$defaults" | sed -n "s/^${name} //p")"
    # (an integration off by default takes auto too)
    if [ -f "${OM818_DIR}/integrations/${name#om818_}/integration.sh" ]; then default=auto; fi
    value="$(setting "$name")"
    case "${default}:${value}" in
    on:on | on:off | off:on | off:off | auto:auto | auto:on | auto:off) ;;
    notify:notify | notify:auto | notify:off) ;;
    on:* | off:*) invalid="${invalid} ${name}=${value} (on or off)" ;;
    auto:*) invalid="${invalid} ${name}=${value} (auto, on or off)" ;;
    notify:*) invalid="${invalid} ${name}=${value} (notify, auto or off)" ;;
    esac
  done
  # (env_sandbox_only skips unknown names silently)
  # shellcheck disable=SC2154 # set by config_load
  for name in $om818_sandboxes; do
    case "$name" in
    drop | container | toolbox | distrobox | chroot | flatpak) ;;
    *) invalid="${invalid} om818_sandboxes:${name} (drop, container, toolbox, distrobox…)" ;;
    esac
  done
  if [ -n "$unknown" ]; then printf 'unknown settings:%s' "$unknown"; fi
  if [ -n "$unknown" ] && [ -n "$invalid" ]; then printf '; '; fi
  if [ -n "$invalid" ]; then printf 'invalid values:%s' "$invalid"; fi
  if [ -n "${unknown}${invalid}" ]; then printf '\n'; fi
}

# Print the URL of a docs page (or folder) for the installed release (main, for a development
# version)
# usage: docs_url <path>
docs_url() {
  local ref kind=blob
  ref="$(on_release)" || ref='main'
  case "$1" in *.md | *.md#*) ;; *) kind=tree ;; esac
  printf 'https://github.com/nathan818fr/oh-my-818/%s/%s/%s\n' "$kind" "$ref" "$1"
}

# Print the om818_* settings (defaults.sh, then the user's config) as name=value lines, an array's
# items joined by spaces (lists of words, e.g. commands), tables left out.
# zsh reads them, else bash 4.4+ (macOS's /bin/bash is 3.2: it can't read defaults.sh's tables).
# (zsh -f: without the user's startup files; output dropped: it would mix with the name=value lines;
# the shell's errors go to stderr, naming the file and line)
config_dump() {
  if command -v zsh >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    zsh -fc '
      source "$2" >/dev/null || exit 1
      if [[ -r "$1" ]]; then source "$1" >/dev/null || exit 1; fi
      for n in ${(ko)parameters[(I)om818_*]}; do
        if [[ "${parameters[$n]}" == association* ]]; then continue; fi
        printf "%s=%s\n" "$n" "${(P)n}"
      done
    ' om818 "$OM818_CONFIG" "${OM818_DIR}/defaults.sh"
  elif bash_supported; then
    # shellcheck disable=SC2016
    bash -c '
      source "$2" >/dev/null || exit 1
      if [[ -r "$1" ]]; then source "$1" >/dev/null || exit 1; fi
      for n in $(compgen -v om818_); do
        if [[ "$(declare -p "$n" 2>/dev/null)" == "declare -A"* ]]; then continue; fi
        eval "printf \"%s=%s\\n\" \"\$n\" \"\${${n}[*]}\""
      done
    ' om818 "$OM818_CONFIG" "${OM818_DIR}/defaults.sh"
  else
    error 'oh-my-818 needs zsh, or bash 4.4 or newer: install one (e.g. sudo apt install zsh),'
    info '  then run the installer again'
    return 1
  fi
}

# Whether a file is the current user's or root's: commands from a folder another user owns could
# run code as this user (e.g. a Homebrew installed by another account on a shared Mac)
# usage: trusted_path <path>
trusted_path() {
  local option line
  # Both a link and its target (-L): either could be swapped by its owner. ls -n: the owner's id
  # (stat isn't portable), split by the shell (some minimal images have no awk)
  for option in -ldn -ldnL; do
    # shellcheck disable=SC2012
    line="$(ls "$option" -- "$1" 2>/dev/null)" || return 1
    set -f
    # shellcheck disable=SC2086 # split on purpose
    set -- "$1" $line
    set +f
    if [ "${4:-}" != 0 ] && [ "${4:-}" != "$(id -u)" ]; then return 1; fi
    set -- "$1"
  done
}

# Whether the bash on PATH is 4.4 or newer, the oldest oh-my-818 supports
bash_supported() {
  if ! command -v bash >/dev/null 2>&1; then return 1; fi
  # shellcheck disable=SC2016
  bash -c '[ "${BASH_VERSINFO[0]}" -gt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }' 2>/dev/null
}

# Print a string quoted for sh, between single quotes (without forking: env_generate quotes every
# value)
quote() {
  local rest="$1" out=''
  while :; do
    case "$rest" in
    *"'"*)
      out="${out}${rest%%"'"*}'\\''"
      rest="${rest#*"'"}"
      ;;
    *) break ;;
    esac
  done
  printf "'%s'\n" "${out}${rest}"
}

# Print the value of a setting (sh has no ${!name})
setting() {
  eval "printf '%s\n' \"\${${1}:-}\""
}

# Print the version of the installed checkout: its release, else a description of the commit
version() {
  local tag
  if tag="$(on_release)"; then
    printf '%s\n' "$tag"
  else
    git -C "$OM818_DIR" describe --tags --always --dirty 2>/dev/null || printf 'unknown\n'
  fi
}

# Print the release the checkout is on (status 1 when it isn't on one)
on_release() {
  local tags tag
  tags="$(git -C "$OM818_DIR" tag -l --points-at HEAD 'v[0-9]*' 2>/dev/null)" || return 1
  for tag in $tags; do
    if is_release "$tag"; then
      printf '%s\n' "$tag"
      return 0
    fi
  done
  return 1
}

# Print the latest release known locally (empty when none)
latest_tag() {
  local tags tag
  tags="$(git -C "$OM818_DIR" tag -l 'v[0-9]*' --sort=-v:refname)"
  for tag in $tags; do
    if is_release "$tag"; then
      printf '%s\n' "$tag"
      return 0
    fi
  done
}

# Whether a tag is a release: vX.Y.Z. Any other tag (v1.0.0-rc1, a test tag) is never installed:
# git's version sort puts v1.0.0-rc1 after v1.0.0, so it would be taken as the latest
is_release() {
  case "${1#v}" in
  "$1" | *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
  *.*.*) return 0 ;;
  *) return 1 ;;
  esac
}

# Whether this install can update itself (a read-only install, e.g. mounted in a sandbox, can't)
updatable() {
  [ -d "${OM818_DIR}/.git" ] && [ -w "${OM818_DIR}/.git" ]
}
