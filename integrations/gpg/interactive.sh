# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Only on a terminal (else tty prints "not a tty"); zsh has it in $TTY, bash asks tty
if [[ -t 0 ]]; then export GPG_TTY="${TTY:-$(tty)}"; fi
