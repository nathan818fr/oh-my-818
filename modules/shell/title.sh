# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Terminal title (zsh and bash): the running command, else the directory; with the host in front
# when the prompt shows it (om818_prompt_host: over SSH, as root…). Control characters are
# replaced: a hostile directory name could otherwise drive the terminal (e.g. set the clipboard)

# Terminals known to handle the title sequence (OSC 2); others, e.g. the Linux console, would
# print it
case "$TERM" in
xterm* | rxvt* | alacritty* | foot* | kitty* | wezterm* | konsole* | st* | screen* | tmux*)
  function _om818_title_precmd() {
    local dir="$PWD"
    if [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]]; then dir="~${dir#"$HOME"}"; fi
    _om818_title "$dir"
  }
  # The command line as typed (its first line); not one starting with a space, which stays out of
  # the history too (e.g. one holding a password)
  function _om818_title_preexec() {
    if [[ "$1" == [[:space:]]* ]]; then return 0; fi
    _om818_title "${1%%$'\n'*}"
  }
  function _om818_title() {
    printf '\e]2;%s\a' "${_om818_host:+${_om818_host}: }${1//[[:cntrl:]]/?}"
  }
  if [[ "$om818_shell" == 'zsh' ]]; then
    _om818_hook_add precmd_functions _om818_title_precmd
  elif [[ "${PROMPT_COMMAND[*]:-}" != *_om818_title_precmd* ]]; then
    # bash: an entry of PROMPT_COMMAND, after the system's title entries (Fedora's /etc/bashrc,
    # VTE's vte.sh), before bash-preexec's install entry when the user loaded it first (init.bash
    # says why). In PROMPT_COMMAND's form: an array item, else a line (bash-preexec before 0.7
    # reads a string). Added once, also when bash-preexec joined the entries into one string
    # shellcheck disable=SC2016 # bash-preexec's entry: 0.7's, then the older ones' first line
    _om818_bps=('__bp_install "$_"' '__bp_trap_string="$(trap -p DEBUG)"')
    if [[ "${_om818_pc-$(declare -p PROMPT_COMMAND 2>/dev/null)}" == 'declare -a'* ]]; then
      _om818_items=()
      for _om818_item in "${PROMPT_COMMAND[@]}"; do
        case "$_om818_item" in
        # (an older bash-preexec adds its lines at the end of an item: the title line goes just
        # before them)
        *"${_om818_bps[1]}"*)
          _om818_rest="${_om818_bps[1]}${_om818_item#*"${_om818_bps[1]}"}"
          _om818_item="${_om818_item%%"${_om818_bps[1]}"*}_om818_title_precmd"$'\n'"$_om818_rest"
          ;;
        *"${_om818_bps[0]}"*) _om818_items+=(_om818_title_precmd) ;;
        esac
        _om818_items+=("$_om818_item")
      done
      if [[ "${_om818_items[*]:-}" != *_om818_title_precmd* ]]; then
        _om818_items+=(_om818_title_precmd)
      fi
      PROMPT_COMMAND=("${_om818_items[@]}")
      unset _om818_items _om818_rest
    else
      # shellcheck disable=SC2178,SC2128
      _om818_item="${PROMPT_COMMAND:-}"
      for _om818_bp in "${_om818_bps[@]}"; do
        if [[ "$_om818_item" == *"$_om818_bp"* ]]; then
          _om818_rest="${_om818_bp}${_om818_item#*"$_om818_bp"}"
          _om818_item="${_om818_item%%"$_om818_bp"*}_om818_title_precmd"$'\n'"$_om818_rest"
          break
        fi
      done
      if [[ "$_om818_item" != *_om818_title_precmd* ]]; then
        _om818_item="${_om818_item:+${_om818_item}$'\n'}_om818_title_precmd"
      fi
      # shellcheck disable=SC2178,SC2128
      PROMPT_COMMAND="$_om818_item"
      unset _om818_bp _om818_rest
    fi
    unset _om818_bps _om818_item
  fi
  _om818_hook_add preexec_functions _om818_title_preexec
  ;;
esac
