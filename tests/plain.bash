# Sourced by the tests in bash: print a prompt string as plain text (without what \001 and \002
# surround: the colors)
function plain() {
  local p="$1"
  while [[ "$p" == *$'\001'*$'\002'* ]]; do p="${p%%$'\001'*}${p#*$'\002'}"; done
  printf '%s\n' "$p"
}
# Run the theme's precmd, then print the prompt as plain text
# shellcheck disable=SC2154 # _om818_ps1: set by the theme
function print_prompt() {
  prompt_om818-classic_precmd
  plain "$_om818_ps1"
}
