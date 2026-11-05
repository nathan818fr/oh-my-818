# shellcheck shell=sh
# `om818 uninstall` (POSIX sh, sourced by bin/om818 after lib/startup-files.sh): the install undone
# without touching the user's data. Their files (~/.config/om818) stay; the history goes back to
# the shells' own files; the folders tools moved to (the xdg integration) are listed, not moved.

uninstall() {
  local default="${XDG_DATA_HOME:-${HOME}/.local/share}/om818" leftovers file line
  # (its copies hold the startup files' content)
  umask 077
  if ! updatable; then
    error "this install is read-only ($(tilde "$OM818_DIR")): remove it where it comes from"
    return 1
  fi
  if command -v zsh >/dev/null 2>&1; then find_zdotdir; fi
  # (before the environment goes: they are what the integrations set up)
  leftovers="$(uninstall_leftovers)"
  release_startup_files
  uninstall_startup_files
  uninstall_history
  rm -rf -- "$OM818_STATE_DIR" "$OM818_CACHE_DIR"
  info ''
  if same_dir "$OM818_DIR" "$default"; then
    rm -rf -- "$OM818_DIR"
    info 'oh-my-818 is uninstalled.'
  else
    # (a checkout elsewhere may be a development one)
    info "oh-my-818 is uninstalled, but not removed from $(tilde "$OM818_DIR"): remove it yourself."
  fi
  # (a shell started from this one, even with exec, keeps oh-my-818's variables, ZDOTDIR included:
  # zsh would read no startup file; a desktop's apps keep them until the next login)
  if [ -n "${SSH_CONNECTION:-}" ]; then
    info '  Log out and connect again (this shell, and any started from it, keep its variables).'
  else
    info '  Open a new terminal (on a Linux desktop, log out and back in: apps keep its variables'
    info '  until then).'
  fi
  info "Your files stay in $(tilde "$OM818_CONFIG_DIR"): delete the folder if you don't need them."
  if [ -n "$leftovers" ]; then
    info 'Left as they are:'
    while IFS='	' read -r file line; do info "  $(tilde_text "${file}: ${line}")"; done <<EOF
$leftovers
EOF
  fi
}

# Remove the lines marked "# om818" from the startup files, in place (links and modes kept), and
# the files left empty (those the installer created). zsh then reads ~/.zshrc again: the files set
# aside as status suggests (~/.zshrc.pre-om818…) go back; what the user added to ZDOTDIR's .zshrc
# since is theirs to copy back
uninstall_startup_files() {
  local file zrc='' kept='' deleted='' tmp="${OM818_STATE_DIR}/uninstall.tmp.$$" status restored=''
  if grep -qs 'ZDOTDIR=.* # om818$' "${HOME}/.zshenv"; then zrc="$(zdotdir)/.zshrc"; fi
  mkdir -p -- "$OM818_STATE_DIR"
  while IFS= read -r file; do
    if [ ! -f "$file" ] || ! grep -qs ' # om818$' "$file"; then continue; fi
    if [ ! -w "$file" ]; then
      info "warning: $(tilde "$file") is read-only: remove its lines marked # om818 yourself"
      continue
    fi
    # The file is rewritten only from a complete copy (grep: 1 when no line is left, 2 on error)
    status=0
    # (byte for byte: in a UTF-8 locale, GNU grep takes a file holding another encoding's bytes,
    # or a NUL, for binary, and would drop those lines)
    LC_ALL=C grep -a -v ' # om818$' "$file" >"$tmp" || status=$?
    if [ "$status" -gt 1 ]; then
      info "warning: cannot read $(tilde "$file"): remove its lines marked # om818 yourself"
      continue
    fi
    if ! cat -- "$tmp" >"$file"; then
      # (it may be cut short: its content goes to ~/.om818-<name>; if even that fails, stop here,
      # the copy still in the state folder)
      if ! mv -f -- "$tmp" "${HOME}/.om818-${file##*/}"; then
        error "cannot rewrite $(tilde "$file"), which may be cut short: its content, without" \
          "oh-my-818's lines, is in $(tilde "$tmp")"
        return 1
      fi
      info "warning: cannot rewrite $(tilde "$file"): its content, without oh-my-818's lines, is"
      info "  in $(tilde "${HOME}/.om818-${file##*/}")"
      continue
    fi
    if [ -s "$file" ]; then
      kept="${kept:+${kept}, }$(tilde "$file")"
    else
      rm -f -- "$file"
      deleted="${deleted:+${deleted}, }$(tilde "$file")"
    fi
  done <<EOF
$(startup_files)
EOF
  rm -f -- "$tmp"
  if [ -n "$kept" ]; then startup_info "removed from ${kept}"; fi
  if [ -n "$deleted" ]; then startup_info "deleted, as nothing else was in them: ${deleted}"; fi
  # (unless a read-only ~/.zshenv kept the ZDOTDIR line)
  if ! grep -qs 'ZDOTDIR=.* # om818$' "${HOME}/.zshenv"; then
    for file in .zshrc .zprofile .zlogin .zlogout; do
      if [ ! -f "${HOME}/${file}.pre-om818" ]; then continue; fi
      # (written since, e.g. by a tool's installer: the user's to merge, the copy kept)
      if [ -s "${HOME}/${file}" ]; then
        info "$(tilde "${HOME}/${file}.pre-om818") (your ${file} before oh-my-818) is kept:"
        info "  ~/${file} was written since. Copy what you need from it, then:"
        info "  mv ~/${file}.pre-om818 ~/${file}"
      elif mv -f -- "${HOME}/${file}.pre-om818" "${HOME}/${file}"; then
        # (protection made it read-only while it was ~/${file})
        chmod u+w "${HOME}/${file}"
        info "$(tilde "${HOME}/${file}") is back (it was set aside as ${file}.pre-om818)."
        if [ "$file" = .zshrc ]; then restored=1; fi
      fi
    done
  fi
  if [ -n "$zrc" ] && ! grep -qs 'ZDOTDIR=.* # om818$' "${HOME}/.zshenv"; then
    # (a line of the user's, or the system's, may keep zsh on that folder)
    find_zdotdir
    if [ -n "$_OM818_ZSH_ZDOTDIR" ]; then return 0; fi
    if [ -s "$zrc" ] && [ -n "$restored" ]; then
      info "zsh reads ~/.zshrc again, not $(tilde "$zrc"): copy the lines you added there since."
    elif [ -s "$zrc" ]; then
      info "zsh reads ~/.zshrc again, not $(tilde "$zrc"): copy your lines from it to ~/.zshrc."
    fi
    # (only when empty: the folder may hold other files)
    rmdir -- "${zrc%/*}" 2>/dev/null || true
  fi
}

# The history: oh-my-818's file (the old one copied at install, then every command since) goes back
# to ~/.<shell>_history when that file is gone and no startup file sets HISTFILE (e.g. the Arch
# wiki's); else both stay, with the command to use it (the old file may have lines of its own, so
# no merge)
uninstall_history() {
  local shell old new own
  for shell in zsh bash; do
    old="${HOME}/.${shell}_history"
    new="$(history_file "$shell")"
    if [ ! -s "$new" ]; then continue; fi
    own="$(history_own_files "$shell")" || true
    # One file through a link, hard or symbolic (the user's own layout): left as it is. (-ef isn't
    # POSIX, but dash, busybox and bash have it: it follows links; a link itself is never moved)
    # shellcheck disable=SC3013
    if [ "$old" -ef "$new" ]; then
      info "$(tilde "$new") and $(tilde "$old") are one file: left as it is"
    elif [ -z "$own" ] && [ ! -e "$old" ] && [ ! -L "$old" ] && [ ! -L "$new" ]; then
      mv -- "$new" "$old"
      info "your ${shell} history is back in $(tilde "$old")"
      # (only when empty: the folder may hold other files)
      rmdir -- "$(dirname -- "$new")" 2>/dev/null || true
    elif [ -n "$own" ]; then
      own="$(printf '%s\n' "$own" | head -n 1)"
      info "$(tilde "$own") sets HISTFILE: $(tilde "$new") is left as it is (the ${shell}"
      info "  commands typed since the install are there)"
    else
      info "oh-my-818's ${shell} history stays in $(tilde "$new"). To use it from now on, in place"
      info "  of $(tilde "$old"): mv $(tilde "$new") $(tilde "$old")"
    fi
  done
}

# Print what the integrations that are on leave behind: "<path><tab><what to do>" per line
uninstall_leftovers() {
  local name
  for name in $(integration_names); do
    (
      integration_eval "$name"
      if [ "$_OM818_I_STATE" = 'on' ] &&
        command -v om818_integration_uninstall >/dev/null 2>&1; then
        om818_integration_uninstall
      fi
    )
  done
}
