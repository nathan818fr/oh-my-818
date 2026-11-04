# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Key bindings, close to the zsh module's (ohmyzsh's): history search, word moves

# Only with line editing (not in `bash -i -c` without a terminal)
if [[ -o emacs || -o vi ]]; then
  # Up/down: the previous/next command starting with what is typed (\e[A: normal cursor mode,
  # \eOA: application mode)
  bind '"\e[A": history-search-backward'
  bind '"\e[B": history-search-forward'
  bind '"\eOA": history-search-backward'
  bind '"\eOB": history-search-forward'
  # Ctrl+left/right: by word
  bind '"\e[1;5C": forward-word'
  bind '"\e[1;5D": backward-word'
  # Option+right/left (macOS terminals sending them as Alt or Meta+arrows: iTerm2, kitty…)
  bind '"\e[1;3C": forward-word'
  bind '"\e[1;3D": backward-word'
  bind '"\e[1;9C": forward-word'
  bind '"\e[1;9D": backward-word'
  # Ctrl+Delete: delete a word
  bind '"\e[3;5~": kill-word'
fi
