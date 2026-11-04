# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# clipcopy [file] and clippaste (zsh and bash), with the platform's clipboard tool: macOS, WSL,
# Wayland, X11, else tmux's buffer

# WSL: Windows' own tools, by their path (Windows' folders may not be on PATH)
_om818_win='/mnt/c/Windows/System32'

if [[ "$OSTYPE" == darwin* ]] && _om818_which pbcopy; then
  function clipcopy() { pbcopy <"${1:-/dev/stdin}"; }
  function clippaste() { pbpaste; }
elif [[ -n "${WSL_DISTRO_NAME:-}" && -x "${_om818_win}/clip.exe" ]]; then
  # clip.exe reads the console's code page unless the text is UTF-16 (with its BOM: iconv's
  # UTF-16); PowerShell prints CRLF line ends, in the console's code page unless told
  function clipcopy() {
    iconv -f UTF-8 -t UTF-16 <"${1:-/dev/stdin}" | /mnt/c/Windows/System32/clip.exe
  }
  function clippaste() {
    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command \
      '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Clipboard -Raw' | tr -d '\r'
  }
elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && _om818_which wl-copy && _om818_which wl-paste; then
  function clipcopy() { wl-copy <"${1:-/dev/stdin}"; }
  function clippaste() { wl-paste --no-newline; }
elif [[ -n "${DISPLAY:-}" ]] && _om818_which xclip; then
  function clipcopy() { xclip -selection clipboard -in <"${1:-/dev/stdin}"; }
  function clippaste() { xclip -selection clipboard -out; }
elif [[ -n "${DISPLAY:-}" ]] && _om818_which xsel; then
  function clipcopy() { xsel --clipboard --input <"${1:-/dev/stdin}"; }
  function clippaste() { xsel --clipboard --output; }
elif [[ -n "${TMUX:-}" ]] && _om818_which tmux; then
  # -w (tmux 3.2+): also the terminal's clipboard, through tmux (e.g. over SSH: your computer's,
  # when the terminal allows it); an older tmux rejects the option before reading anything
  function clipcopy() { tmux load-buffer -w "${1:--}" 2>/dev/null || tmux load-buffer "${1:--}"; }
  function clippaste() { tmux save-buffer -; }
else
  function clipcopy() {
    printf '%s: no clipboard tool: install wl-clipboard (Wayland) or xclip (X11); SSH: tmux\n' \
      clipcopy >&2
    return 1
  }
  function clippaste() {
    printf '%s: no clipboard tool: install wl-clipboard (Wayland) or xclip (X11); SSH: tmux\n' \
      clippaste >&2
    return 1
  }
fi
unset _om818_win
