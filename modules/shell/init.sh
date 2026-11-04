# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Start of the zsh and bash modules (code valid in both, sourced by modules/<shell>/init.*, which
# set om818_shell and define _om818_which and _om818_now first): the environment, then the config.

# Set for om818's commands only, never for the shells' children (e.g. a tmux server they start):
# OM818_PROBE (the shell om818 starts to inspect the setup) is read here, OM818_LOCKED dropped
typeset -g _om818_probe="${OM818_PROBE:-}"
unset OM818_PROBE OM818_LOCKED

typeset -g _om818_config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/om818"
typeset -g _om818_state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/om818"
typeset -g _om818_cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/om818"
# A temporary install (install.sh --temp): all in its folder, if it is one of the user's (not
# another user's, e.g. through sudo keeping the variable)
if [[ -n "${OM818_TEMP:-}" ]] &&
  [[ "$OM818_TEMP" != /* || -L "$OM818_TEMP" || ! -O "$OM818_TEMP" ]]; then
  unset OM818_TEMP
fi
if [[ -n "${OM818_TEMP:-}" ]]; then
  _om818_config_dir="${OM818_TEMP}/config"
  _om818_state_dir="${OM818_TEMP}/state"
  _om818_cache_dir="${OM818_TEMP}/cache"
fi

# A root shell keeping another user's HOME (some sudo setups, macOS's): it must not create files
# there that this user then can't change. History and update check are skipped, the environment
# is only read, and root's caches go to root's own folder
typeset -g _om818_foreign_home=''
if [[ ! -O "$HOME" ]]; then
  _om818_foreign_home=1
  if [[ "$EUID" -eq 0 ]]; then _om818_cache_dir=~root/.cache/om818; fi
fi

# The environment, regenerated (with a line for config typos) when config.sh or the version
# changed (.git/HEAD is rewritten by every checkout). Sourced again then, when the startup files
# didn't load it (plugin managers), or on a reload (env.d/ may have changed). Not regenerated in
# a probe: it inspects the setup (e.g. status, which reports an outdated env.sh)
function _om818_load_env() {
  local env="${_om818_state_dir}/env.sh" fresh=0
  # (config.sh removed: its folder changed since)
  if [[ -z "$_om818_foreign_home" && -z "$_om818_probe" ]] && [[ ! -r "$env" ||
    "${_om818_config_dir}/config.sh" -nt "$env" || "${OM818_DIR}/.git/HEAD" -nt "$env" ||
    (! -e "${_om818_config_dir}/config.sh" && "$_om818_config_dir" -nt "$env") ]]; then
    # (in /: a tool there could read the folder's config, e.g. a mise shim)
    (cd / && "${OM818_DIR}/bin/om818" env --quiet --check) || return 0
    fresh=1
  fi
  # (om818_path_prepend comes from env.sh: defined means it is already loaded)
  if [[ "$fresh" -eq 1 || -n "${_om818_loaded:-}" ]]; then
    source -- "$env"
  elif ! typeset -f om818_path_prepend >/dev/null; then
    source -- "$env"
  fi
}
_om818_load_env
unset -f _om818_load_env

# Add a function to a hook array (precmd_functions, preexec_functions) unless it is there already:
# loading oh-my-818 again (e.g. `source ~/.zshrc` to reload it) adds nothing twice
# usage: _om818_hook_add <array> <function>
function _om818_hook_add() {
  local f
  local -a hooks
  eval "hooks=(\"\${${1}[@]}\")"
  for f in "${hooks[@]}"; do
    if [[ "$f" == "$2" ]]; then return 0; fi
  done
  eval "${1}+=(\"\$2\")"
}

# Whether this shell sees the temporary install's shells (the PID namespace recorded in pid-ns): one
# started in another (e.g. bwrap --unshare-pid, inside a session) would take them for gone
function _om818_temp_same_ns() {
  local ns=''
  { IFS= read -r ns <"${OM818_TEMP}/pid-ns"; } 2>/dev/null || return 0
  [[ -z "$ns" || "$(command ls -Ldi /proc/self/ns/pid 2>/dev/null)" == "${ns} "* ]]
}

# A temporary install (install.sh --temp): each shell registers in sessions/<pid>. The last one to
# exit removes the folder, under setup.lock (held by install.sh while a session sets up), and
# clears the entries of dead shells. A closed terminal or a dropped connection sends a second
# SIGHUP (the shell the line was typed in passing it on): ignored once the hook runs
if [[ -n "${OM818_TEMP:-}" && -d "${OM818_TEMP}/sessions" ]] && _om818_temp_same_ns; then
  # (the folder as checked above: the variable may change in the session, the hook removes it)
  typeset -g _om818_temp_dir="$OM818_TEMP"
  { : >|"${_om818_temp_dir}/sessions/$$"; } 2>/dev/null
  # (`bash` typed here stays temporary, as `zsh` does through ZDOTDIR: the wrapper SHELL names)
  # shellcheck disable=SC2139 # expanded now, on purpose
  if [[ -x "${_om818_temp_dir}/bin/bash" ]]; then alias bash="${_om818_temp_dir}/bin/bash"; fi
  function _om818_temp_exit() {
    local entry made='' tries
    # (zsh runs zshexit in a subshell that exits, e.g. `(exit)`, with the shell's $$)
    # (globbing as by default, whatever the user's options: with noglob or failglob, live shells'
    # entries would go unseen and the folder be removed)
    if [[ -n "${ZSH_VERSION:-}" ]]; then
      if ((ZSH_SUBSHELL > 0)); then return 0; fi
      setopt local_options glob null_glob
    else
      set +f
      shopt -u failglob nullglob
    fi
    trap '' HUP INT TERM
    if [[ -z "${_om818_temp_dir:-}" ]]; then return 0; fi
    rm -f -- "${_om818_temp_dir}/sessions/$$"
    # (held by another shell exiting: waited for, up to 2 s; by a session setting up: it
    # registers, so the folder stays)
    tries=0
    until mkdir -- "${_om818_temp_dir}/setup.lock" 2>/dev/null; do
      # (removed meanwhile, by the shell exiting with this one)
      if [[ ! -d "${_om818_temp_dir}/sessions" ]]; then return 0; fi
      tries=$((tries + 1))
      if ((tries > 20)); then return 0; fi
      sleep 0.1
    done
    { printf '%s\n' "$$" >|"${_om818_temp_dir}/setup.lock/pid"; } 2>/dev/null
    for entry in "${_om818_temp_dir}"/sessions/*; do
      if [[ ! -e "$entry" ]]; then continue; fi
      if kill -0 "${entry##*/}" 2>/dev/null; then
        rm -rf -- "${_om818_temp_dir}/setup.lock"
        return 0
      fi
      rm -f -- "$entry"
    done
    if [[ -e "${_om818_temp_dir}/parent-made" ]]; then made=1; fi
    rm -rf -- "$_om818_temp_dir"
    # (its parent, ~/.cache, when the install made it: if left empty)
    if [[ -n "$made" ]]; then rmdir -- "${_om818_temp_dir%/*}" 2>/dev/null || true; fi
  }
  # (a hang-up: the hook runs before the default action ends the shell)
  if [[ "$om818_shell" == 'zsh' ]]; then
    _om818_hook_add zshexit_functions _om818_temp_exit
    function TRAPHUP() {
      _om818_temp_exit
      exit 129
    }
  else
    # bash's own HUP handler, which this trap replaces, passes the hang-up on to the jobs (to each
    # job's process group): done here too. Also on an exit with no terminal left (an EOF read
    # before the HUP came)
    trap '_om818_temp_exit; if [[ ! -t 0 ]]; then _om818_temp_hup; fi' EXIT
    trap '_om818_temp_exit; _om818_temp_hup; exit 129' HUP
    function _om818_temp_hup() {
      local IFS=$' \t\n'
      local -a jobs
      # shellcheck disable=SC2207 # pids: split on purpose
      jobs=($(jobs -p))
      if ((${#jobs[@]} > 0)); then kill -HUP -- "${jobs[@]/#/-}" 2>/dev/null; fi
    }
  fi
fi

# macOS: in login shells (every Terminal tab), /etc/zprofile (zsh) or /etc/profile (bash) runs
# path_helper after the environment was loaded, which puts the system's folders first again
# (Apple's git and python before Homebrew's or mise's): the environment's own go back in front,
# as om818_path_prepend left them (OM818_PATH_FRONT: in the order they were added, each in front)
function _om818_path_front() {
  local dir rest="${OM818_PATH_FRONT:-}:"
  while [[ "$rest" == *:* ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    if [[ -z "$dir" ]]; then continue; fi
    om818_path_remove "$dir"
    PATH="${dir}:${PATH}"
  done
}

# Every setting with its default, then the user's
source -- "${OM818_DIR}/defaults.sh"
if [[ -r "${_om818_config_dir}/config.sh" ]]; then
  source -- "${_om818_config_dir}/config.sh"
fi

# The host's short name, when the prompt and the terminal title show it (om818_prompt_host; auto:
# over SSH, as root, or under sudo: where running a command on the wrong machine is easy)
typeset -g _om818_host=''
if [[ "$om818_prompt_host" == 'on' || ("$om818_prompt_host" == 'auto' &&
  (-n "${SSH_CONNECTION:-}" || "$EUID" -eq 0 || -n "${SUDO_USER:-}")) ]]; then
  _om818_host="${HOST:-${HOSTNAME:-}}"
  _om818_host="${_om818_host%%.*}"
fi
