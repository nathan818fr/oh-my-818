# History: in the state folder, private, written as commands run; shared between open shells with
# om818_history_share (else each shell sees the others' commands once restarted)

# The same size in memory and in the file: zsh loads at most HISTSIZE and rewrites the file from
# memory when it trims it, so a bigger SAVEHIST would be lost
HISTSIZE="$om818_history_size"
SAVEHIST="$om818_history_size"

# A temporary install (install.sh --temp): the host's usual file, its mode as is, never trimmed
# (zsh trims it once 20% over SAVEHIST)
if [[ -n "${OM818_TEMP:-}" ]]; then
  # (oh-my-818's own while the account has it installed, the one its shells read: not a file
  # left by an uninstall, nor another user's, e.g. through su keeping XDG_STATE_HOME)
  HISTFILE="${XDG_STATE_HOME:-${HOME}/.local/state}/zsh/history"
  if [[ ! -d "${XDG_DATA_HOME:-${HOME}/.local/share}/om818/.git" || ! -f "$HISTFILE" ||
    ! -O "$HISTFILE" ]]; then
    HISTFILE="${HOME}/.zsh_history"
  fi
  SAVEHIST=1000000000
# Root keeping another user's HOME (sudo): history in memory only, the file would become root's
elif [[ -z "$_om818_foreign_home" ]]; then
  HISTFILE="${XDG_STATE_HOME:-${HOME}/.local/state}/zsh/history"
  () {
    local -a mode
    if [[ ! -f "$HISTFILE" ]]; then
      # Created private (umask in a subshell: the shell's own stays)
      if ! mkdir -p -- "${HISTFILE:h}" || ! (umask 077 && : >>"$HISTFILE"); then return 0; fi
    fi
    zmodload -F zsh/stat b:zstat
    if zstat -o -A mode +mode -- "$HISTFILE" 2>/dev/null && [[ "${mode[1]}" != *600 ]]; then
      chmod 600 "$HISTFILE"
      print -ru2 -- "oh-my-818: made your history file private (chmod 600 ${HISTFILE/#$HOME/~})"
    fi
  }
else
  unset HISTFILE
fi

setopt extended_history hist_ignore_dups hist_ignore_space hist_verify append_history
# Each command is written at once (not when the shell exits): share_history does it too, and
# zsh's manual says not to set both
if [[ "$om818_history_share" == 'on' ]]; then
  setopt share_history no_inc_append_history
else
  setopt no_share_history inc_append_history
fi
