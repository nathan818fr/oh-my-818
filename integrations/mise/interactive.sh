# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Not cached: its output contains the current PATH. Once: a reload (`source ~/.bashrc`) would add
# its hook again (in bash, bash-preexec merged it where mise doesn't look)
if ! typeset -f _mise_hook >/dev/null; then eval "$(mise activate "$om818_shell")"; fi
