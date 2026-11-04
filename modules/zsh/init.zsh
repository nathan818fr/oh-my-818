# The zsh module: the environment and config (shared with bash), each feature, the integrations
# and the prompt. Settings: defaults.sh, then ~/.config/om818/config.sh.

if [[ ! -o interactive ]]; then return 0; fi

# For the code shared with bash
typeset -g om818_shell=zsh

# Set REPLY to the path of a command (status 1 if there is none). Not ${commands[…]}: a name it
# lacks makes zsh read every folder of PATH (hash_list_all), slow with Windows' folders in WSL
function _om818_which() {
  local dir
  for dir in "${path[@]}"; do
    if [[ -n "${WSL_DISTRO_NAME:-}" && "$dir" == /mnt/[a-z]/* ]]; then continue; fi
    if [[ -f "${dir}/${1}" && -x "${dir}/${1}" ]]; then
      REPLY="${dir}/${1}"
      return 0
    fi
  done
  REPLY=''
  return 1
}

# Set REPLY to the current time, in seconds since the epoch
function _om818_now() {
  REPLY="$EPOCHSECONDS"
}

zmodload -F zsh/datetime p:EPOCHSECONDS
# The hook arrays, declared: with no_unset (some users' option), reading them would fail
typeset -ga precmd_functions preexec_functions chpwd_functions zshexit_functions
source -- "${OM818_DIR}/modules/shell/init.sh"
if [[ "$OSTYPE" == darwin* && -o login ]]; then _om818_path_front; fi

# zsh's files in HOME aren't read with ZDOTDIR elsewhere: the first start says so for those holding
# something (a distribution's untouched default aside), later ones when one changes (e.g. a tool's
# installer added a line to ~/.zshrc). A read-only file (a guard against such installers) never
# changes
() {
  local seen="${_om818_state_dir}/zsh-files-seen" file zdir="${ZDOTDIR/#$HOME/~}"
  local -a changed=()
  if [[ "${ZDOTDIR:-$HOME}" == "$HOME" || -n "$_om818_foreign_home" || -n "${OM818_TEMP:-}" ]]
  then
    return 0
  fi
  for file in .zshrc .zprofile .zlogin; do
    if [[ ! -s "${HOME}/${file}" ]]; then continue; fi
    # (later, a read-only file can't have changed: a protected one, a guard)
    if [[ -e "$seen" ]]; then
      if [[ -w "${HOME}/${file}" && "${HOME}/${file}" -nt "$seen" ]]; then
        changed+=("~/${file}")
      fi
    elif ! cmp -s -- "${HOME}/${file}" "/etc/skel/${file}"; then
      changed+=("~/${file}")
    fi
  done
  if [[ "${#changed[@]}" -gt 0 && -e "$seen" ]]; then
    print -ru2 -- "oh-my-818: ${changed[*]} changed (a tool's installer?), but zsh reads" \
      "${zdir}/ instead: move the new lines to the file of the same name there"
  elif [[ "${#changed[@]}" -gt 0 ]]; then
    print -ru2 -- "oh-my-818: zsh no longer reads ${changed[*]}: it reads ${zdir}/ instead." \
      "Copy your lines (aliases to shell.d/, exports to env.d/, tool blocks to ${zdir}/.zshrc;" \
      "not oh-my-zsh's), then set the file aside: docs/coming-from.md in oh-my-818's" \
      "repository. Shown once."
  fi
  if mkdir -p -- "${seen%/*}" 2>/dev/null; then { : >|"$seen"; } 2>/dev/null; fi
}

source -- "${OM818_DIR}/vendor/zsh-defer/zsh-defer.plugin.zsh"

if [[ "$om818_history" != 'off' ]]; then source -- "${OM818_DIR}/modules/zsh/history.zsh"; fi
if [[ "$om818_keys" != 'off' ]]; then
  # (emacs keys, whatever EDITOR is, as oh-my-zsh: vi users set `bindkey -v` in shell.d/)
  source -- "${OM818_DIR}/vendor/ohmyzsh/lib/key-bindings.zsh"
  # Option+right/left (macOS terminals sending them as Alt or Meta+arrows: iTerm2, kitty…), also
  # for vi users (in both modes: unbound, vi's normal mode would read Esc then letters that edit)
  () {
    local keymap
    for keymap in emacs viins vicmd; do
      bindkey -M "$keymap" '^[[1;3C' forward-word
      bindkey -M "$keymap" '^[[1;3D' backward-word
      bindkey -M "$keymap" '^[[1;9C' forward-word
      bindkey -M "$keymap" '^[[1;9D' backward-word
    done
  }
fi
if [[ "$om818_completion" != 'off' ]]; then
  source -- "${OM818_DIR}/modules/zsh/completion.zsh"
elif [[ -n "${skip_global_compinit:-}" && -r /etc/zsh/zshrc && -r /etc/os-release ]] &&
  (( ${${(@f)"$(</etc/os-release)"}[(I)ID*=*ubuntu]} )); then
  # (the system's own compinit, which the environment skips for oh-my-818's: Debian's
  # /etc/zsh/zshrc runs it only on Ubuntu, with this same test)
  autoload -Uz compinit && compinit
fi
if [[ "$om818_title" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/title.sh"; fi
if [[ "$om818_clipboard" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/clipboard.sh"; fi
unsetopt beep
# Comments typed or pasted at the prompt (`ls # list`), as in bash
setopt interactive_comments

source -- "${OM818_DIR}/modules/shell/integrations.sh"
if [[ "$om818_theme" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/prompt.sh"; fi
if [[ "$om818_update" != 'off' ]]; then source -- "${OM818_DIR}/modules/shell/update.sh"; fi

# Only needed while starting
unset -f _om818_which _om818_cached _om818_now _om818_files_of _om818_same_time _om818_stamp
unset REPLY
typeset -g _om818_loaded=1
