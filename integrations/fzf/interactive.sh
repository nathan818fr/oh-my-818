# shellcheck shell=bash disable=SC1090,SC1091,SC2154
if _om818_cached fzf "--${om818_shell}"; then source -- "$REPLY"; fi
