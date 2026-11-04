# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Generated completions: in the cache, where each shell looks for them (zsh: fpath; bash:
# bash-completion's user dirs), refreshed in the background, used from the next shell on
if [[ "$om818_shell" == 'zsh' ]]; then
  # (a loop, not " ${fpath[*]} ": a user's IFS would change that join)
  _om818_dir=''
  for _om818_dir in "${fpath[@]}"; do
    if [[ "$_om818_dir" == "${_om818_cache_dir}/completions" ]]; then break; fi
    _om818_dir=''
  done
  if [[ -z "$_om818_dir" ]]; then fpath+=("${_om818_cache_dir}/completions"); fi
  unset _om818_dir
elif [[ ":${BASH_COMPLETION_USER_DIR:-}:" != *":${_om818_cache_dir}/bash-completion:"* ]]; then
  # (the default user dir is kept after ours: setting the variable replaces it)
  _om818_dir="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/bash-completion}"
  BASH_COMPLETION_USER_DIR="${_om818_cache_dir}/bash-completion:${_om818_dir}"
  unset _om818_dir
fi

# Generate the missing or outdated completions of tools.list. A file is outdated when its tool's
# binary changed: another path, links resolved (kept in <dir>-bin/<name>, as a completion file
# holds only the completion), or another modification time (it gets the binary's, like
# _om818_cached's files). A command that fails leaves an empty file: not retried until the binary
# changes
function _om818_completions_update() {
  local dir file name cmd bin seen line
  if [[ "$om818_shell" == 'zsh' ]]; then
    dir="${_om818_cache_dir}/completions"
  else
    dir="${_om818_cache_dir}/bash-completion/completions"
  fi
  cd / || return 0 # (a tool may read the folder's config, e.g. a mise shim)
  if [[ ! -d "$dir" ]]; then mkdir -p -- "$dir" || return 0; fi
  while read -r name cmd; do
    case "$name" in '' | '#'*) continue ;; esac
    cmd="${cmd//\{shell\}/${om818_shell}}"
    file="${dir}/${name}"
    if [[ "$om818_shell" == 'zsh' ]]; then file="${dir}/_${name}"; fi
    if ! _om818_which "$name" || ! _om818_which "${cmd%% *}"; then continue; fi
    _om818_resolved "$REPLY"
    bin="$REPLY"
    # Provided by something else (the tool's package, zsh-completions): leave it
    if _om818_completion_elsewhere "$name" "$dir"; then
      if [[ -e "$file" ]]; then rm -f -- "$file"; fi
      continue
    fi
    seen="${dir}-bin/${name}"
    if [[ -e "$file" ]] && _om818_same_time "$bin" "$file" &&
      { IFS= read -r line <"$seen"; } 2>/dev/null &&
      [[ "$line" == "$bin" ]]; then
      continue
    fi
    # ($$: the shell's pid, also in this background subshell: each shell its own temporary file.
    # OP_CACHE=false: else 1Password's `op` starts a daemon, which stays. With a throwaway
    # XDG_CONFIG_HOME: `op` makes its config folder, which would stay, empty)
    if ! (export OP_CACHE=false XDG_CONFIG_HOME="${file}.config.$$" &&
      eval "$cmd") >|"${file}.tmp.$$" 2>/dev/null; then
      : >|"${file}.tmp.$$"
    fi
    rm -rf -- "${file}.config.$$"
    _om818_stamp "$bin" "${file}.tmp.$$" "$file"
    # zsh reads new completion files when it rebuilds its dump: for a new one, rebuilt at the next
    # start (an updated one is read from its file, as the dump only lists the names)
    if [[ ! -e "$file" && -s "${file}.tmp.$$" && -n "${ZSH_COMPDUMP:-}" ]]; then
      rm -f -- "$ZSH_COMPDUMP" "${ZSH_COMPDUMP}.zwc"
    fi
    mv -f -- "${file}.tmp.$$" "$file"
    mkdir -p -- "${seen%/*}" && printf '%s\n' "$bin" >|"$seen"
  done <"${OM818_DIR}/integrations/tool_completions/tools.list"
}

# Whether a completion for a command exists outside our directory
function _om818_completion_elsewhere() {
  local d
  if [[ "$om818_shell" == 'zsh' ]]; then
    for d in "${fpath[@]}"; do
      if [[ "$d" != "$2" && -e "${d}/_${1}" ]]; then return 0; fi
    done
  else
    for d in "${XDG_DATA_HOME:-${HOME}/.local/share}/bash-completion/completions" \
      /usr/share/bash-completion/completions /usr/local/share/bash-completion/completions \
      "${HOMEBREW_PREFIX:-/opt/homebrew}/share/bash-completion/completions" \
      /etc/bash_completion.d; do
      if [[ -e "${d}/${1}" || -e "${d}/${1}.bash" ]]; then return 0; fi
    done
  fi
  return 1
}

# (in a subshell: not a job of this shell, so no "[1] Done" notice)
(_om818_completions_update >/dev/null 2>&1 &)
unset -f _om818_completions_update _om818_completion_elsewhere
