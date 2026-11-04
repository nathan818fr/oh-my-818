# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# starship draws the prompt: oh-my-818's theme stays off. (--print-full-init: the script itself,
# not the stub that runs starship again at each start)
if _om818_cached starship init "$om818_shell" --print-full-init; then
  source -- "$REPLY"
  # shellcheck disable=SC2034 # read by the module, which then skips the theme
  om818_theme=off
fi
