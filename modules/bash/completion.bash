# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Completion: the system's bash-completion, loaded here if the system didn't (Debian, Ubuntu and
# Fedora load it from /etc; Homebrew's needs this)

if ! declare -F _comp_initialize >/dev/null && ! declare -F _init_completion >/dev/null &&
  ! shopt -oq posix; then
  for _om818_file in /usr/share/bash-completion/bash_completion /etc/bash_completion \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/etc/profile.d/bash_completion.sh" \
    /usr/local/etc/profile.d/bash_completion.sh; do
    if [[ -r "$_om818_file" ]]; then
      source -- "$_om818_file"
      break
    fi
  done
  unset _om818_file
fi

# Case-insensitive, listed at the first Tab, colored like ls (only with line editing: not in
# `bash -i -c` without a terminal)
if [[ -o emacs || -o vi ]]; then
  bind 'set completion-ignore-case on'
  bind 'set show-all-if-ambiguous on'
  bind 'set colored-stats on'
  bind 'set mark-symlinked-directories on'
fi
