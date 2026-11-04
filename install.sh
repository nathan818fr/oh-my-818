#!/bin/sh
set -eu

# Install oh-my-818: clone it, check out its latest release, then hand over to that release's
# `om818 install` (which wires the shell startup files). Run it again to repair an install.
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)"
# With --temp: a temporary install instead (temp_main), for a one-time session on a machine.
# This file runs from main, for every release. --temp's layout (the folder's files, sessions/,
# setup.lock, parent-made, pid-ns, OM818_TEMP) is shared with the release's
# modules/shell/init.sh: a change must keep working with every release (OM818_REF can pick an
# older one).
#
# Environment:
#   OM818_REPO  repository to clone (default: GitHub)
#   OM818_REF   tag, branch or commit to check out instead of the latest release

OM818_REPO="${OM818_REPO:-https://github.com/nathan818fr/oh-my-818.git}"
OM818_REF="${OM818_REF:-}"
OM818_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/om818"
# 1 while a clone made here isn't installed yet: removed if the install fails
_OM818_CLONED=0
# The topmost folder above the clone made here (~/.local): removed with it if empty
_OM818_PARENT=''
# A temporary install's folder, while this process sets it up (temp_main): removed if it fails
# and no other session uses it
_OM818_TEMP_SETUP=''
# 1 once oh-my-818's own install runs: stopping then leaves it half-way
_OM818_HANDED=0

main() {
  local dir
  # Exported by tools like vcsh, yadm or git hooks, these would point git at another repository
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE
  # (git --version: macOS has a /usr/bin/git that only offers to install the developer tools)
  if ! git --version >/dev/null 2>&1; then
    printf 'error: oh-my-818 needs git: install it first' >&2
    if [ "$(uname -s)" = 'Darwin' ]; then
      printf ' (xcode-select --install)' >&2
    else
      printf ' (e.g. sudo apt install git, sudo dnf install git)' >&2
    fi
    printf '\n' >&2
    return 1
  fi
  # Through sudo, root would install into a home folder it doesn't own: its files there would
  # belong to root (test -O isn't POSIX; ls -n: the owner's id, the 3rd word; -L: through a link)
  # shellcheck disable=SC2012,SC2046
  if [ "$(id -u)" -eq 0 ] &&
    [ "$(set -f && set -- $(ls -ldnL -- "$HOME") && echo "$3")" != 0 ]; then
    printf 'error: run the installer as yourself, without sudo (root has its own install:\n' >&2
    printf '  sudo -i, then the install line)\n' >&2
    return 1
  fi
  trap cleanup EXIT
  # (dash runs no EXIT trap on a signal: exit through it)
  trap 'stopped 130' INT
  trap 'stopped 143' TERM
  trap 'stopped 129' HUP
  if [ -n "${OM818_TEMP:-}" ]; then
    printf 'error: this terminal runs a temporary install: exit it first\n' >&2
    return 1
  fi
  # (before cloning anything: oh-my-818 can't work without one)
  pick_shell >/dev/null || return 1
  case "${1:-}" in
  '') ;;
  --temp)
    temp_main
    return
    ;;
  *)
    printf 'error: unknown argument: %s (--temp: a temporary install)\n' "$1" >&2
    return 2
    ;;
  esac

  if [ -d "${OM818_DIR}/.git" ]; then
    printf 'oh-my-818 is already in %s: repairing it\n' "$(tilde "$OM818_DIR")" >&2
    if ! fetch 2>/dev/null; then
      printf 'warning: cannot reach %s (offline?): repairing with the release already here\n' \
        "$(git -C "$OM818_DIR" remote get-url origin 2>/dev/null)" >&2
    fi
  elif [ -e "$OM818_DIR" ]; then
    printf 'error: %s exists but is not a clone of oh-my-818: move it away first\n' \
      "$(tilde "$OM818_DIR")" >&2
    return 1
  else
    printf 'Cloning oh-my-818 into %s\n' "$(tilde "$OM818_DIR")" >&2
    dir="$(dirname -- "$OM818_DIR")"
    while [ ! -d "$dir" ]; do
      _OM818_PARENT="$dir"
      dir="$(dirname -- "$dir")"
    done
    mkdir -p -- "$(dirname -- "$OM818_DIR")"
    _OM818_CLONED=1
    if ! git clone --quiet -- "$OM818_REPO" "$OM818_DIR"; then
      printf 'error: cannot clone %s (offline?)\n' "$OM818_REPO" >&2
      return 1
    fi
  fi

  # (a version asked for wins over an update cut short earlier, which om818 install would finish)
  if [ -n "$OM818_REF" ]; then
    rm -f -- "${XDG_STATE_HOME:-${HOME}/.local/state}/om818/install-pending"
  fi
  checkout_release "$_OM818_CLONED"

  # Kept from here on, even if the install stops half-way: it may have changed the startup files,
  # and its om818 can finish (this script again) or undo (om818 uninstall) what it did
  _OM818_CLONED=0
  _OM818_HANDED=1
  if ! "${OM818_DIR}/bin/om818" install; then
    half_way
    return 1
  fi
  _OM818_HANDED=0
}

# Check out the latest release, unless asked for another version (OM818_REF); a repaired install
# already on a release keeps it
# usage: checkout_release <just cloned: 0 or 1>
checkout_release() {
  local ref="$OM818_REF"
  if [ -z "$ref" ] && { [ "$1" -eq 1 ] || ! on_release; }; then
    ref="$(latest_release)"
    if [ -z "$ref" ]; then
      printf 'error: no release yet. For the development version, run the install line with\n' >&2
      # shellcheck disable=SC2016 # shown as is
      printf '  OM818_REF=main in front: OM818_REF=main sh -c "$(curl …)"\n' >&2
      return 1
    fi
    ref="refs/tags/${ref}"
  elif [ -n "$ref" ] && is_tag "$ref"; then
    # A tag: before a branch of the same name
    ref="refs/tags/${ref}"
  elif [ -n "$ref" ] && git -C "$OM818_DIR" rev-parse -q --verify "origin/${ref}" >/dev/null; then
    # A branch: as fetched, not the local copy a previous install left behind
    ref="origin/${ref}"
  fi
  if [ -n "$ref" ]; then
    git -C "$OM818_DIR" -c advice.detachedHead=false checkout --quiet --detach "$ref"
  fi
}

# A temporary install: oh-my-818 in a private folder, then a shell on it (pick_shell). Each shell
# registers (modules/shell/init.sh), and the last to exit removes the folder; sessions at the same
# time share it
temp_main() {
  local folder shell entry
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf 'error: --temp starts a shell: run it in a terminal\n' >&2
    return 1
  fi
  shell="$(pick_shell)" || return 1
  folder="$(temp_folder)" || return 1
  temp_take "$folder" || return 1
  # Checked again under the lock: its last shell may have removed it meanwhile, and another made
  # it again
  if ! temp_private "$folder" || [ ! -d "${folder}/sessions" ]; then
    _OM818_TEMP_SETUP=''
    printf 'error: %s changed during the setup: run the line again\n' "$folder" >&2
    return 1
  fi
  # No shell left: the files are from killed sessions (maybe an older release): made anew
  for entry in "$folder"/sessions/*; do break; done
  if [ ! -e "$entry" ]; then
    rm -rf -- "${folder:?}/om818" "${folder:?}/state" "${folder:?}/cache" "${folder:?}/config" \
      "${folder:?}/zdotdir" "${folder:?}/bashrc" "${folder:?}/bin"
  fi
  OM818_DIR="${folder}/om818"
  if [ -d "${OM818_DIR}/.git" ] && [ -n "$OM818_REF" ]; then
    printf 'warning: another session uses the release there: OM818_REF left out\n' >&2
  fi
  if [ ! -d "${OM818_DIR}/.git" ]; then
    printf 'Cloning oh-my-818 into %s (temporary)\n' "$(tilde "$OM818_DIR")" >&2
    if ! git clone --quiet -- "$OM818_REPO" "$OM818_DIR"; then
      printf 'error: cannot clone %s (offline?)\n' "$OM818_REPO" >&2
      return 1
    fi
    checkout_release 1
  fi
  # (a release older than temporary installs, e.g. through OM818_REF)
  if ! grep -qs OM818_TEMP -- "${OM818_DIR}/lib/common.sh"; then
    printf 'error: this release has no temporary install: a newer one is needed\n' >&2
    return 1
  fi
  OM818_TEMP="$folder"
  export OM818_TEMP
  # The first session's setup (a second one uses it as it is)
  if [ ! -e "${folder}/config/config.sh" ]; then
    mkdir -p -- "${folder}/config" "${folder}/zdotdir" "${folder}/bin"
    # Its settings: no update (the next temporary install takes the latest release), nothing that
    # writes to the home folder (the xdg integration's folders, tools' generated completions)
    printf '%s\n' '# A temporary install (install.sh --temp)' 'om818_update=off' 'om818_xdg=off' \
      'om818_tool_completions=off' >"${folder}/config/config.sh"
    if ! "${OM818_DIR}/bin/om818" env --quiet; then
      printf 'error: cannot run oh-my-818 from %s (a folder mounted noexec?): set\n' "$folder" >&2
      printf '  XDG_RUNTIME_DIR (or XDG_CACHE_HOME) to a private folder that can run programs\n' >&2
      return 1
    fi
    temp_files "$folder" "$shell"
  fi
  # This process becomes the shell (exec): registered under its pid, before the lock goes
  : >"${folder}/sessions/$$"
  temp_release "$folder"
  printf 'oh-my-818 %s, temporary: removed once its last shell exits\n' \
    "$(git -C "$OM818_DIR" describe --tags --always 2>/dev/null)" >&2
  # (its om818 first: the shell running this line may have the host's oh-my-818)
  PATH="${OM818_DIR}/bin:${PATH}"
  export PATH
  if [ "${shell##*/}" = zsh ]; then
    ZDOTDIR="${folder}/zdotdir"
    SHELL="$shell"
    export ZDOTDIR SHELL
    exec "$shell"
  fi
  # bash has no ZDOTDIR: SHELL is a wrapper starting bash with the rc file, for the shells started
  # from it (e.g. tmux's)
  SHELL="${folder}/bin/bash"
  export SHELL
  exec "$shell" --rcfile "${folder}/bashrc" -i
}

# Write the startup files: zsh's (ZDOTDIR), bash's (--rcfile), and bin/bash, the wrapper SHELL
# names. They load oh-my-818 for the folder's owner only: another user (root through sudo -s,
# keeping SHELL or ZDOTDIR) gets their own rc file
# usage: temp_files <folder> <shell>
# shellcheck disable=SC2016 # written as is
temp_files() {
  local folder uid bash
  folder="$(temp_quote "$1")"
  uid="$(id -u)"
  printf '%s\n' "if [[ \"\$EUID\" == ${uid} ]]; then" "  export OM818_TEMP=${folder}" \
    "  source $(temp_quote "${1}/om818/om818.plugin.zsh")" 'else' '  ZDOTDIR="$HOME"' \
    '  if [[ -r ~/.zshrc ]]; then source ~/.zshrc; fi' 'fi' >"${1}/zdotdir/.zshrc"
  # (read before the system's zshrc: Ubuntu's runs compinit, which oh-my-818 runs itself)
  printf '%s\n' "if [[ \"\$EUID\" == ${uid} ]]; then skip_global_compinit=1; fi" \
    >"${1}/zdotdir/.zshenv"
  printf '%s\n' "if [[ \"\$EUID\" == ${uid} ]]; then" "  export OM818_TEMP=${folder}" \
    "  source $(temp_quote "${1}/om818/om818.plugin.bash")" \
    'elif [[ -r ~/.bashrc ]]; then' '  source ~/.bashrc' 'fi' >"${1}/bashrc"
  # The wrapper's bash: a bash 4.4+, also when this first session is zsh (a later one may pick
  # bash). None: no wrapper, since no session can pick bash
  bash="$2"
  if [ "${bash##*/}" != bash ]; then bash="$(SHELL=bash pick_shell 2>/dev/null)" || bash=''; fi
  if [ "${bash##*/}" != bash ]; then return 0; fi
  # A login bash ignores --rcfile: -l and --login are dropped, also from a group (-lc → -c, -il →
  # -i), among the shell's own options only (up to --, - or a command); no argument left: -i
  {
    printf '%s\n' '#!/bin/sh' \
      "if [ \"\$(id -u)\" != ${uid} ]; then exec $(temp_quote "$bash") \"\$@\"; fi"
    cat <<'EOF'
rest='' skip=''
for arg do
  shift
  if [ -n "$skip" ]; then
    skip=''
  elif [ -z "$rest" ]; then
    case "$arg" in
    -l | --login) continue ;;
    - | --) rest=1 ;;
    -o | +o | -O | +O | --rcfile | --init-file) skip=1 ;;
    --*) ;;
    [-+]*)
      case "$arg" in
      *l*)
        arg="$(printf '%s' "$arg" | tr -d l)"
        if [ "$arg" = - ] || [ "$arg" = + ]; then continue; fi
        ;;
      esac
      # (a group holding o or O: its option's name comes next, e.g. -eo pipefail)
      case "$arg" in *[oO]*) skip=1 ;; esac
      ;;
    *) rest=1 ;;
    esac
  fi
  set -- "$@" "$arg"
done
if [ "$#" -eq 0 ]; then set -- -i; fi
EOF
    printf '%s\n' "exec $(temp_quote "$bash") --rcfile $(temp_quote "${1}/bashrc") \"\$@\""
  } >"${1}/bin/bash"
  chmod +x -- "${1}/bin/bash"
}

# Print the folder, made private if missing: in XDG_RUNTIME_DIR when it is private (removed at
# logout), else in the cache folder, one per host (a home shared between machines). Never where
# another user could make it again (temp_closed: not /tmp). A cache folder made here is noted
# (parent-made) and removed with it. Status 1 when it can't be such a folder
temp_folder() {
  local parent="${XDG_CACHE_HOME:-}" folder host made='' real ns='' pidns
  case "$parent" in /*) ;; *) parent="${HOME%/}/.cache" ;; esac
  # (as one name: a host name may hold any character, / too)
  host="$(uname -n)"
  host="$(printf '%s' "$host" | tr -c 'A-Za-z0-9._-' _)"
  # A container with its own PID namespace (not the host's, 4026531836) gets its own folder: it
  # shares the home folder or XDG_RUNTIME_DIR, but can't see the host's shells
  ns="$(ls -Ldi /proc/self/ns/pid 2>/dev/null)" || ns=''
  ns="${ns%% *}"
  case "$ns" in *[!0-9]*) ns='' ;; esac
  pidns="$ns"
  case "$ns" in '' | 4026531836) ns='' ;; *) ns="-${ns}" ;; esac
  folder="${parent%/}/om818-temp-${host}${ns}"
  case "${XDG_RUNTIME_DIR:-}" in
  /*)
    if temp_private "$XDG_RUNTIME_DIR" && real="$(temp_real "$XDG_RUNTIME_DIR")" &&
      temp_closed "$real"; then
      parent="$real"
      folder="${real%/}/om818-temp${ns}"
    fi
    ;;
  esac
  # The parent first (made when missing, in a folder that passes the same check). Each path is
  # resolved once (temp_real), then that string is checked and used: resolved again, a link could
  # lead elsewhere by then (temp_closed refuses a link in it)
  if [ ! -d "$parent" ] && real="$(temp_real "$(dirname -- "$parent")")" &&
    temp_closed "$real" &&
    (umask 077 && mkdir -- "${real%/}/$(basename -- "$parent")") 2>/dev/null; then
    made=1
  fi
  real="$(temp_real "$parent")" || real=''
  if [ -z "$real" ] || ! temp_closed "$real"; then
    printf 'error: %s is missing, or others can change it (or a folder above it): set\n' \
      "$parent" >&2
    printf '  XDG_RUNTIME_DIR (or XDG_CACHE_HOME) to a private folder of yours\n' >&2
    return 1
  fi
  parent="$real"
  folder="${parent%/}/${folder##*/}"
  # (private: a setgid or default ACL parent would give it other bits, or an ACL)
  if (umask 077 && mkdir -- "$folder") 2>/dev/null; then
    chmod u=rwx,go=,g-s -- "$folder" 2>/dev/null || true
  fi
  if [ ! -e "$folder" ] && [ ! -L "$folder" ]; then
    printf 'error: cannot make %s: set XDG_RUNTIME_DIR (or XDG_CACHE_HOME) to a private folder\n' \
      "$folder" >&2
    return 1
  fi
  if ! temp_private "$folder"; then
    printf 'error: %s exists, but is not a private folder of yours: remove it\n' "$folder" >&2
    return 1
  fi
  if [ -n "$made" ]; then : >"${folder}/parent-made"; fi
  mkdir -p -- "${folder}/sessions"
  # (for the shells: one in another PID namespace, e.g. bwrap inside a session, can't see the
  # others, and would take them for gone)
  if [ -n "$pidns" ] && [ ! -e "${folder}/pid-ns" ]; then
    printf '%s\n' "$pidns" >"${folder}/pid-ns"
  fi
  printf '%s\n' "$folder"
}

# Print a folder's real path (no link in it)
temp_real() {
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

# Whether a folder, and each one above it, are the user's or root's, the folder closed to others
# (no write access for group or others), those above too unless sticky (/tmp: what is in it stays
# its owner's). As given: a link in the path is refused (its mode starts with l)
# shellcheck disable=SC2012,SC2046
temp_closed() {
  local dir="$1" uid top=1
  uid="$(id -u)"
  case "$dir" in /*) ;; *) return 1 ;; esac
  while :; do
    set -- $(set -f && set -- $(ls -ldn -- "$dir" 2>/dev/null) && echo "${1:-} ${3:-}")
    if [ "${2:-}" != "$uid" ] && [ "${2:-}" != 0 ]; then return 1; fi
    case "${1:-}" in
    d????-??-*) ;;
    d????????[tT]*) if [ "$top" -eq 1 ]; then return 1; fi ;;
    *) return 1 ;;
    esac
    if [ "$dir" = / ]; then return 0; fi
    top=0
    dir="${dir%/*}"
    dir="${dir:-/}"
  done
}

# Whether a folder is a private one of the user's: no link, rwx for its owner only (macOS may add
# @ or + after the mode)
# shellcheck disable=SC2012,SC2046
temp_private() {
  local mode
  mode="$(set -f && set -- $(ls -ldn -- "$1" 2>/dev/null) && echo "${1:-}")"
  [ ! -L "$1" ] && [ -d "$1" ] && temp_mine "$1" && [ "${mode#drwx------}" != "$mode" ]
}

# Whether a file is the current user's (ls -n: the owner's id, the 3rd word)
# shellcheck disable=SC2012,SC2046
temp_mine() {
  [ "$(set -f && set -- $(ls -ldn -- "$1") && echo "$3")" = "$(id -u)" ]
}

# Take the folder's setup lock (setup.lock, holding the owner's pid): one session set up at a time,
# and its last shell can't remove it meanwhile. A lock whose owner is gone (or without a pid for 5
# s) is taken over; a live owner is waited for, up to 2 minutes (a slow clone). Then clear the
# entries of shells gone (killed without their exit hook)
temp_take() {
  local lock="${1}/setup.lock" tries=0 nopid=0 pid entry
  until mkdir -- "$lock" 2>/dev/null; do
    if [ ! -d "$1" ]; then
      printf 'error: %s was removed during the setup: run the line again\n' "$1" >&2
      return 1
    fi
    # (not taken by another: it can't be made, e.g. a full disk; unless released just then)
    if [ ! -d "$lock" ]; then
      if mkdir -- "$lock" 2>/dev/null; then break; fi
      if [ ! -d "$lock" ]; then
        printf 'error: cannot write in %s (a full disk?)\n' "$1" >&2
        return 1
      fi
    fi
    pid="$(cat -- "${lock}/pid" 2>/dev/null)" || pid=''
    if [ -z "$pid" ]; then nopid=$((nopid + 1)); else nopid=0; fi
    # (no pid yet: just made, or its owner killed right then: a few seconds)
    if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ "$nopid" -gt 5 ]; then
      rm -rf -- "$lock"
      nopid=0
    else
      if [ "$tries" -eq 3 ]; then
        printf 'Waiting for another session to set up the temporary install\n' >&2
      fi
      sleep 1
    fi
    tries=$((tries + 1))
    if [ "$tries" -gt 120 ]; then
      printf 'error: another session is still setting up %s\n' "$1" >&2
      return 1
    fi
  done
  printf '%s\n' "$$" >"${lock}/pid"
  _OM818_TEMP_SETUP="$1"
  for entry in "$1"/sessions/*; do
    if [ -e "$entry" ] && ! kill -0 "${entry##*/}" 2>/dev/null; then rm -f -- "$entry"; fi
  done
}

# Release the setup lock; with "sweep" (a failed setup), remove the folder unless a shell uses it
# usage: temp_release <folder> [sweep]
temp_release() {
  local entry
  _OM818_TEMP_SETUP=''
  if [ "${2:-}" = sweep ]; then
    rm -f -- "${1}/sessions/$$"
    for entry in "$1"/sessions/*; do
      if [ -e "$entry" ]; then
        rm -rf -- "${1}/setup.lock"
        return 0
      fi
    done
    # (and its parent, ~/.cache, when this setup made it: if left empty)
    set -- "$1" "$([ -e "${1}/parent-made" ] && echo made)"
    rm -rf -- "$1"
    if [ -n "$2" ]; then rmdir -- "${1%/*}" 2>/dev/null || true; fi
    return 0
  fi
  rm -rf -- "${1}/setup.lock"
}

# Print the shell for oh-my-818 (the one a temporary install starts): the login shell when it is
# zsh or bash 4.4+, else zsh, else bash 4.4+
pick_shell() {
  local name
  for name in "${SHELL:-}" zsh bash; do
    case "$name" in
    */om818-temp*/bin/bash) continue ;; # (a temporary install's wrapper)
    esac
    case "${name##*/}" in
    zsh) ;;
    bash)
      # shellcheck disable=SC2016
      if ! "$name" -c '((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 &&
        BASH_VERSINFO[1] >= 4)))' >/dev/null 2>&1; then continue; fi
      ;;
    *) continue ;;
    esac
    if name="$(command -v -- "$name")"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  printf 'error: oh-my-818 needs zsh, or bash 4.4 or newer: install one\n' >&2
  return 1
}

# Print a path quoted for sh
temp_quote() {
  printf "'%s'\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The same as bin/om818's (lib/release.sh, lib/common.sh), which can't be used before the release
# is checked out: tags mirror GitHub's (a moved or deleted tag too), git never asks anything
fetch() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    git -C "$OM818_DIR" fetch --quiet --prune --prune-tags --tags --force origin
}

# Print a path with ~ for the home folder
# shellcheck disable=SC2088 # a ~ to show
tilde() {
  case "$1" in
  "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
  *) printf '%s\n' "$1" ;;
  esac
}

# Whether a tag of that name exists
is_tag() {
  git -C "$OM818_DIR" rev-parse -q --verify "refs/tags/${1}" >/dev/null
}

# Whether the checkout is on a release
on_release() {
  local tag
  for tag in $(git -C "$OM818_DIR" tag -l --points-at HEAD 'v[0-9]*'); do
    if is_release "$tag"; then return 0; fi
  done
  return 1
}

# Print the latest release (empty when none)
latest_release() {
  local tags tag
  tags="$(git -C "$OM818_DIR" tag -l 'v[0-9]*' --sort=-v:refname)"
  for tag in $tags; do
    if is_release "$tag"; then
      printf '%s\n' "$tag"
      return 0
    fi
  done
}

# Whether a tag is a release (vX.Y.Z)
is_release() {
  case "${1#v}" in
  "$1" | *[!0-9.]* | .* | *. | *..* | *.*.*.*) return 1 ;;
  *.*.*) return 0 ;;
  *) return 1 ;;
  esac
}

# A first install failing before oh-my-818's own install leaves nothing behind (the clone); a
# temporary one, its folder unless another session uses it
cleanup() {
  local dir
  # (a second signal, e.g. the terminal's HUP after Ctrl+C, would stop it half-way)
  trap '' HUP INT TERM
  if [ -n "$_OM818_TEMP_SETUP" ]; then temp_release "$_OM818_TEMP_SETUP" sweep; fi
  if [ "$_OM818_CLONED" -eq 1 ]; then
    rm -rf -- "$OM818_DIR"
    dir="$(dirname -- "$OM818_DIR")"
    while [ -n "$_OM818_PARENT" ] && rmdir -- "$dir" 2>/dev/null &&
      [ "$dir" != "$_OM818_PARENT" ]; do
      dir="$(dirname -- "$dir")"
    done
  fi
}

# On a signal (Ctrl+C, a closed terminal): exit through the EXIT trap, saying how to go on
stopped() {
  if [ "$_OM818_HANDED" -eq 1 ]; then half_way; fi
  exit "$1"
}

half_way() {
  printf 'error: the install stopped half-way: run the install line again to finish it, or\n' >&2
  printf '  %s/bin/om818 uninstall to undo it\n' "$(tilde "$OM818_DIR")" >&2
}

# (main runs from this line, after the whole file is read: a script piped from curl, or edited
# while it runs, is never run half-read)
eval 'main "$@";exit "$?"'
