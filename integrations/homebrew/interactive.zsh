# Completions of the tools installed with Homebrew: zsh only looks in /usr/local/share (Intel Macs),
# not in /opt/homebrew (Apple Silicon) or Linuxbrew's prefix. Before compinit, which runs later
if [[ -n "${HOMEBREW_PREFIX:-}" && -d "${HOMEBREW_PREFIX}/share/zsh/site-functions" &&
  ${fpath[(Ie)${HOMEBREW_PREFIX}/share/zsh/site-functions]} -eq 0 ]]; then
  fpath=("${HOMEBREW_PREFIX}/share/zsh/site-functions" "${fpath[@]}")
fi
