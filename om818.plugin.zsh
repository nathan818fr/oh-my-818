# oh-my-818's zsh entry point: sourced by $ZDOTDIR/.zshrc, or loaded by a zsh plugin manager.
# Its folder, absolute (%x: the file being sourced; :A resolves links)
typeset -g OM818_DIR="${${(%):-%x}:A:h}"
source -- "${OM818_DIR}/modules/zsh/init.zsh"
