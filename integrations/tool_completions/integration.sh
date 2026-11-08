# shellcheck shell=sh disable=SC2034
# Completions for tools that ship none for the shell but can print one (tools.list): generated
# in the background into the cache, and again when the tool's binary changes

# Not with completion off: nothing would load them
om818_integration_check() {
  if [ "$(setting om818_completion)" = 'off' ]; then
    printf 'om818_completion=off\n'
    return 1
  fi
}
