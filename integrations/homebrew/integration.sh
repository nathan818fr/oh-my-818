# shellcheck shell=sh disable=SC2034
# Homebrew: its prefix on PATH and its HOMEBREW_* variables, like `brew shellenv` (not its MANPATH
# and INFOPATH: man and info find Homebrew's pages through PATH); zsh: its completions
# (https://brew.sh)

om818_integration_check() {
  local bin path
  if ! bin="$(_om818_homebrew_brew)"; then
    printf 'brew not found\n'
    return 1
  fi
  # (brew, its folder: another user's could run code as you)
  for path in "$bin" "${bin%/*}"; do
    if ! trusted_path "$path"; then
      printf '%s belongs to another user: left out (it could run code as you)\n' "$path"
      return 1
    fi
  done
}

om818_integration_env() {
  local bin prefix repository
  bin="$(_om818_homebrew_brew)"
  prefix="$("$bin" --prefix)"
  repository="$("$bin" --repository)"
  # The folders put first on PATH: absolute, and the user's or root's
  case "$prefix" in /*) ;; *) return 0 ;; esac
  if ! trusted_path "${prefix}/bin"; then return 0; fi
  if [ -e "${prefix}/sbin" ] && ! trusted_path "${prefix}/sbin"; then return 0; fi
  env_set HOMEBREW_PREFIX "$prefix"
  env_set HOMEBREW_CELLAR "${prefix}/Cellar"
  env_set HOMEBREW_REPOSITORY "$repository"
  env_path_prepend "${prefix}/sbin"
  env_path_prepend "${prefix}/bin"
}

# Print where brew is: it isn't on PATH before this integration runs
_om818_homebrew_brew() {
  local bin
  for bin in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew \
    "${HOME}/.linuxbrew/bin/brew"; do
    if [ -x "$bin" ]; then
      printf '%s\n' "$bin"
      return 0
    fi
  done
  return 1
}
