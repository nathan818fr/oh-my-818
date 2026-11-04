# shellcheck shell=sh disable=SC2034
# fzf: fuzzy finder for Ctrl+R (history), Ctrl+T (files) and Alt+C (cd)
# (https://junegunn.github.io/fzf/). Off by default: it replaces the shell's Ctrl+R
om818_integration_tool=fzf

# fzf 0.48 brought `fzf --zsh` and `fzf --bash`, its setup (Debian 12 and Ubuntu 24.04 ship older)
om818_integration_check() {
  local version major minor
  if ! command -v fzf >/dev/null 2>&1; then return 0; fi
  version="$(fzf --version 2>/dev/null || true)"
  version="${version%% *}"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  case "${major}${minor}" in
  '' | *[!0-9]*) return 0 ;;
  esac
  if [ "$major" -eq 0 ] && [ "$minor" -lt 48 ]; then
    printf 'fzf 0.48+ needed (found %s)\n' "$version"
    return 1
  fi
}
