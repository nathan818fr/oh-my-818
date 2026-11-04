# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# History: in the state folder, private, written as commands run: each shell sees the others'
# commands once restarted. (om818_history_share is zsh's: bash's `history -n` reads from a wrong
# offset once the shell appended its own lines, and reloading the whole file costs each prompt)

# A temporary install (install.sh --temp): the host's usual file, never trimmed (below)
if [[ -n "${OM818_TEMP:-}" ]]; then
  # (oh-my-818's own while the account has it installed, the one its shells read: not a file
  # left by an uninstall, nor another user's, e.g. through su keeping XDG_STATE_HOME)
  HISTFILE="${XDG_STATE_HOME:-${HOME}/.local/state}/bash/history"
  if [[ ! -d "${XDG_DATA_HOME:-${HOME}/.local/share}/om818/.git" || ! -f "$HISTFILE" ||
    ! -O "$HISTFILE" ]]; then
    HISTFILE="${HOME}/.bash_history"
  fi
# Root keeping another user's HOME (sudo): history in memory only, the file would become root's
elif [[ -z "$_om818_foreign_home" ]]; then
  HISTFILE="${XDG_STATE_HOME:-${HOME}/.local/state}/bash/history"
  if [[ ! -f "$HISTFILE" ]]; then
    # Created private (umask in a subshell: the shell's own stays). If it can't be (a folder
    # root made), history in memory only: bash would complain at every prompt
    if ! { mkdir -p -- "${HISTFILE%/*}" && (umask 077 && : >>"$HISTFILE"); } 2>/dev/null; then
      unset HISTFILE
    fi
  fi
else
  unset HISTFILE
fi

# After HISTFILE: setting HISTFILESIZE truncates the current file, the user's own until then
HISTSIZE="$om818_history_size" # the same size in memory and in the file, as in zsh
if [[ -n "${OM818_TEMP:-}" ]]; then
  HISTFILESIZE=-1 # (-1: never cut; a number would cut the host's file)
else
  HISTFILESIZE="$om818_history_size"
fi
HISTCONTROL=ignoreboth # bash-preexec turns it into ignoredups (init.bash handles spaces)
shopt -s histappend    # (bash writes the whole history at exit without it)
shopt -s histverify    # show a history expansion (!!, !$) before running it
# (on a reload, `source ~/.bashrc`, bash-preexec is already installed: it won't adjust it again)
if [[ "${PROMPT_COMMAND[*]:-}" == *__bp_precmd_invoke_cmd* ]]; then __bp_adjust_histcontrol; fi

# Write each command at once, not when the shell exits
function _om818_history_append() {
  if [[ -n "${HISTFILE:-}" ]]; then history -a; fi
}
_om818_hook_add precmd_functions _om818_history_append
