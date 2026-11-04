# Sourced by the tests in zsh: print a prompt string as plain text (expanded, without colors)
setopt extended_glob
function plain() {
  local p="${(%)1}"
  print -r -- "${p//$'\e'\[[0-9;]#m/}"
}
# Run the theme's precmd, then print the prompt as plain text
function print_prompt() {
  prompt_om818-classic_precmd
  plain "$PROMPT"
}
