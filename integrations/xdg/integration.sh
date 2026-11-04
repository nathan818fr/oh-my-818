# shellcheck shell=sh disable=SC2034
# XDG base directories for tools that don't use them by default (tools.list): their files go to
# ~/.config, ~/.local/share, ~/.cache instead of their own dot-folder in HOME. A tool is redirected
# unless only its old location exists: a fresh machine starts clean, a tool already in use stays
# where it is (nothing moves by itself: `om818 status` shows how). Each tool can be turned off
# alone (om818_xdg_<tool>=off). On macOS, it also turns off ~/.zsh_sessions
# (om818_xdg_zsh_sessions=off keeps them).

om818_integration_env() {
  if [ "$(uname -s)" = 'Darwin' ] && [ "$(setting om818_xdg_zsh_sessions)" != 'off' ]; then
    # Apple's Terminal keeps a copy of the history of each window there
    env_set SHELL_SESSIONS_DISABLE 1
  fi
  _om818_xdg_each _om818_xdg_env
}

# For `om818 status`: the variables the user set themselves (they win over these defaults)
om818_integration_note() {
  local names
  names="$(_om818_xdg_each _om818_xdg_own)"
  if [ -n "$names" ]; then printf 'left as you set them: %s\n' "${names% }"; fi
}

# Print the names of a tool's variables set to something else than its row's value
# usage: _om818_xdg_own <tool> <old location>
_om818_xdg_own() {
  local var value bin current
  while IFS='	' read -r var value bin; do
    if [ -z "$var" ]; then continue; fi
    current="$(setting "$var")"
    if [ -n "$current" ] && [ "$current" != "$value" ]; then printf '%s ' "$var"; fi
  done <<EOF
$_om818_xdg_rows
EOF
}

# For `om818 uninstall`: the tools' folders it moved, and the command putting each back
om818_integration_uninstall() {
  _om818_xdg_each _om818_xdg_back
}

# Old locations still in use, for `om818 status`: how to move each, or that both exist
om818_integration_leftovers() {
  _om818_xdg_each _om818_xdg_leftover
}

# Run a function for each tool of tools.list that is on: <function> <tool> <old location>. The
# tool's rows are in _om818_xdg_rows, values expanded: "variable<tab>value<tab>bin" per line (bin:
# a folder to put on PATH, or -). Its first row's location decides for all of them.
_om818_xdg_each() {
  local fn="$1" os tool var value old bin current='' current_old=''
  os="$(uname -s)"
  _om818_xdg_rows=''
  while read -r tool var value old bin; do
    case "$tool" in '' | '#'*) continue ;; esac
    if [ "$(setting "om818_xdg_${tool}")" = 'off' ]; then continue; fi
    # Docker Desktop, a desktop app that reads no env.sh, keeps ~/.docker
    if [ "$tool" = 'docker' ] && [ "$os" = 'Darwin' ]; then continue; fi
    if [ "$tool" != "$current" ]; then
      if [ -n "$current" ]; then "$fn" "$current" "$current_old"; fi
      current="$tool"
      _om818_xdg_expand "$old"
      current_old="$_om818_xdg_v"
      _om818_xdg_rows=''
    fi
    _om818_xdg_expand "$value"
    value="$_om818_xdg_v"
    _om818_xdg_expand "${bin:--}"
    _om818_xdg_rows="${_om818_xdg_rows}${var}	${value}	${_om818_xdg_v}
"
  done <"${OM818_DIR}/integrations/xdg/tools.list"
  if [ -n "$current" ]; then "$fn" "$current" "$current_old"; fi
}

# Set _om818_xdg_v to a value of tools.list, expanded (no fork: called for each value)
_om818_xdg_expand() {
  _om818_xdg_v="$1"
  # shellcheck disable=SC2016,SC2088 # the literal prefixes of tools.list
  case "$1" in
  '~/'*) _om818_xdg_v="${HOME}/${1#'~/'}" ;;
  '$XDG_CONFIG_HOME/'*) _om818_xdg_v="${XDG_CONFIG_HOME:-${HOME}/.config}/${1#*/}" ;;
  '$XDG_DATA_HOME/'*) _om818_xdg_v="${XDG_DATA_HOME:-${HOME}/.local/share}/${1#*/}" ;;
  '$XDG_STATE_HOME/'*) _om818_xdg_v="${XDG_STATE_HOME:-${HOME}/.local/state}/${1#*/}" ;;
  '$XDG_CACHE_HOME/'*) _om818_xdg_v="${XDG_CACHE_HOME:-${HOME}/.cache}/${1#*/}" ;;
  esac
}

# Set _om818_xdg_v to the current tool's main folder (the value of its first row)
_om818_xdg_main() {
  _om818_xdg_v="${_om818_xdg_rows#*	}"
  _om818_xdg_v="${_om818_xdg_v%%	*}"
}

# usage: _om818_xdg_env <tool> <old location>
_om818_xdg_env() {
  local var value bin
  _om818_xdg_main
  if [ -e "$2" ] && [ ! -e "$_om818_xdg_v" ]; then return 0; fi
  while IFS='	' read -r var value bin; do
    if [ -z "$var" ]; then continue; fi
    env_set_default "$var" "$value"
    # In front: e.g. rustup's cargo before a distribution's /usr/bin/cargo; not when the user's own
    # value of the variable won
    if [ "$bin" != '-' ]; then
      # shellcheck disable=SC2016 # written as is
      printf 'if [ "${%s:-}" = %s ]; then om818_path_prepend %s; fi\n' "$var" "$(quote "$value")" \
        "$(quote "$bin")"
    fi
  done <<EOF
$_om818_xdg_rows
EOF
}

# Print "<new location><tab><advice>" when the tool uses its new location only
# usage: _om818_xdg_back <tool> <old location>
_om818_xdg_back() {
  _om818_xdg_main
  if [ ! -e "$_om818_xdg_v" ] || [ -e "$2" ]; then return 0; fi
  printf '%s\twithout oh-my-818, %s uses %s: mv %s %s\n' "$_om818_xdg_v" "$1" "$2" \
    "$_om818_xdg_v" "$2"
}

# Print "<old location><tab><advice>" when the old location exists, unless the user set the tool's
# variables themselves (e.g. GOPATH="$HOME/go" in env.d/: the folder is theirs)
# usage: _om818_xdg_leftover <tool> <old location>
_om818_xdg_leftover() {
  local files='' file
  if [ ! -e "$2" ] || [ -n "$(_om818_xdg_own "$1" "$2")" ]; then return 0; fi
  _om818_xdg_main
  if [ -e "$_om818_xdg_v" ]; then
    printf '%s\tboth it and %s exist (the new one is used): merge them by hand\n' \
      "$2" "$_om818_xdg_v"
    return 0
  fi
  if [ "$1" = 'cargo' ]; then
    # rustup's installer adds a line loading ~/.cargo/env, which fails once the folder moved
    for file in "${HOME}/.profile" "${HOME}/.bashrc" "${HOME}/.bash_profile" "${HOME}/.zshenv" \
      "$(zdotdir)/.zshrc" "${OM818_ENV_D}"/*.sh; do
      if grep -qsF '.cargo/env' "$file"; then files="${files} ${file}"; fi
    done
  fi
  printf '%s\tin use, so not moved: mv %s %s && om818 env' "$2" "$2" "$_om818_xdg_v"
  if [ -n "$files" ]; then
    printf ', then remove the line loading ~/.cargo/env from%s' "$files"
  fi
  printf '\n'
}
