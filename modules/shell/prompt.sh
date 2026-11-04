# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# The prompt theme (code valid in zsh and bash): the shell's prompt layer, gitstatus, then the
# theme (modules/shell/themes/<theme>/theme.sh), set up by its prompt_<theme>_setup.

source -- "${OM818_DIR}/modules/${om818_shell}/prompt.${om818_shell}"
# gitstatusd is downloaded by `om818 install` (also run by updates), never by a starting shell:
# offline, that would wait on the network at every start
GITSTATUS_CACHE_DIR="${_om818_cache_dir}/gitstatus"
GITSTATUS_AUTO_INSTALL=0
if [[ "$om818_shell" == 'zsh' ]]; then
  # shellcheck source=/dev/null # zsh code
  source -- "${OM818_DIR}/vendor/gitstatus/gitstatus.plugin.zsh"
else
  source -- "${OM818_DIR}/vendor/gitstatus/gitstatus.plugin.sh"
fi
if [[ -r "${OM818_DIR}/modules/shell/themes/${om818_theme}/theme.sh" ]]; then
  source -- "${OM818_DIR}/modules/shell/themes/${om818_theme}/theme.sh"
  "prompt_${om818_theme}_setup"
else
  printf 'oh-my-818: unknown theme: %s (om818_theme: om818-classic, or off): no prompt set\n' \
    "$om818_theme" >&2
fi
