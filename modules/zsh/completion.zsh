# Completion: compinit runs once .zshrc is done (ez-compinit queues the compdef calls made
# before), with the zshzoo style and its files in the cache folder

ZSH_COMPDUMP="${_om818_cache_dir}/zcompdump"
# A new version may bring new completions (zsh-completions): rebuild the dump (.git/HEAD is
# rewritten by every checkout)
if [[ "${OM818_DIR}/.git/HEAD" -nt "$ZSH_COMPDUMP" ]]; then
  rm -f -- "$ZSH_COMPDUMP" "${ZSH_COMPDUMP}.zwc"
fi
if [[ "$om818_zsh_completions" != 'off' &&
  ${fpath[(Ie)${OM818_DIR}/vendor/zsh-completions/src]} -eq 0 ]]; then
  fpath+=("${OM818_DIR}/vendor/zsh-completions/src")
fi
zstyle ':plugin:ez-compinit' 'compstyle' 'zshzoo'
# compinit -C with a dump younger than 20 h, else -i: no "insecure directories" question at
# startup (e.g. Homebrew's on a shared Mac). New completion files are seen when the dump is
# rebuilt: oh-my-818 removes it when it adds some (updates, generated completions)
zstyle ':plugin:ez-compinit' 'use-cache' 'yes'
source -- "${OM818_DIR}/vendor/ez-compinit/ez-compinit.plugin.zsh"
# The style also makes globs case-insensitive (`rm *.log` would match A.LOG): only completion is
setopt case_glob
zstyle ':completion::complete:*' cache-path "${_om818_cache_dir}/zcompcache"
