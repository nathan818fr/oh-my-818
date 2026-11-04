# shellcheck shell=bash disable=SC1090,SC1091,SC2154
if _om818_cached direnv hook "$om818_shell"; then source -- "$REPLY"; fi
if [[ "$om818_shell" == bash ]]; then _om818_precmd_first _direnv_hook; fi
