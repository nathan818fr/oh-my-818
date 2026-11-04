# shellcheck shell=bash disable=SC2034
# Every setting, with its default. To change one, copy its line into ~/.config/om818/config.sh
# (create it). For a table (`typeset -gA`), set one key: `om818_prompt_colors[path]=33`.

### Updates

# notify: one line in new terminals when a release is out; auto: install it; off: no check
om818_update=notify

### Shell features, zsh and bash: on or off

om818_history=on         # history in ~/.local/state/<shell>/history, saved as commands run
om818_history_size=20000 # commands kept, in memory and in the file
om818_history_share=off  # zsh only; on: other terminals' commands at once (off: once restarted)
om818_keys=on            # Up/Down search the history for what is typed, Ctrl+arrows by word…
om818_completion=on      # Tab completion, ignoring case (bash: the system's bash-completion)
om818_zsh_completions=on # zsh: extra completions from zsh-users/zsh-completions
om818_title=on           # terminal title: the command, else the folder (and the host over SSH)
om818_clipboard=on       # clipcopy and clippaste commands: macOS, WSL, Wayland, X11, else tmux

# on: startup files read-only, so that installers can't add lines to them (then: om818 install)
om818_protect_startup_files=off

### Sandbox only

# Commands that run only inside a sandbox, for every program that finds them on PATH (terminals,
# scripts, IDEs), e.g. (claude codex): elsewhere they stop with a hint. A reminder, not
# isolation: OM818_SANDBOX_ONLY=off claude runs one anyway
om818_sandbox_only=()
# What counts as one: drop, container (podman, docker…), toolbox, distrobox (these two share your
# home folder), chroot, flatpak
om818_sandboxes=(drop container)

### Integrations: auto (on when the tool is found), on, or off

# Only adding things, auto by default:
om818_mise=auto             # mise: activation, and its shims for scripts, IDEs and desktop apps
om818_podman=auto           # Docker clients (docker, compose, IDEs) use podman (Linux, no Docker)
om818_homebrew=auto         # Homebrew: its prefix on PATH, its zsh completions
om818_direnv=auto           # direnv: loads .envrc files
om818_gpg=auto              # GnuPG: GPG_TTY, for passphrase prompts
om818_1password=auto        # 1Password CLI shell plugins (op plugin init)
om818_tool_completions=auto # completions generated for tools shipping none (gh, rg, fd, uv…)
# Tools' files in ~/.config, ~/.local/share, ~/.cache instead of a hidden folder in your home
# folder, unless only their old folder exists; on macOS, no ~/.zsh_sessions. Per tool: auto or off
om818_xdg=auto
om818_xdg_cargo=auto
om818_xdg_rustup=auto
om818_xdg_go=auto
om818_xdg_gradle=auto
om818_xdg_npm=auto
om818_xdg_docker=auto # not on macOS: Docker Desktop keeps ~/.docker
om818_xdg_zsh_sessions=auto
# Replacing a known behavior, off by default:
om818_fzf=off      # fzf 0.48+: fuzzy Ctrl+R, Ctrl+T, Alt+C
om818_zoxide=off   # zoxide: z <part of a folder's path>
om818_starship=off # starship's prompt instead of the theme (https://starship.rs)

### Prompt

# om818-classic, or off to keep your own prompt
om818_theme=om818-classic

# Segments of each line, in order ("+name": no space before it); leave one out to hide it.
# Segments: status duration env user path git indicators date jobs symbol
om818_prompt_line1=(status duration env user path git indicators)
om818_prompt_line2=(date jobs symbol)
# Environments shown when you are in them (venv, SSH, container…), in this order (all the known
# ones; leave one out to hide it)
om818_prompt_envs=(drop container chroot ssh flatpak nix flox venv conda)
om818_prompt_host=auto         # user@host: auto (over SSH, as root, under sudo), on, off
om818_prompt_default_user=     # a user name to hide, e.g. yours (root and others still show)
om818_prompt_path_depth=0      # folders of the path shown (…/b/c); 0: the whole path
om818_prompt_date_format=%H:%M # strftime format, e.g. %I:%M %p (man strftime)
om818_prompt_date_tz=          # time zone of the clock (e.g. UTC); empty: local time
om818_prompt_status_sticky=off # on: Enter on an empty line keeps the last ✘ (off: ✔ again)
om818_prompt_duration_min=3    # seconds a command must take to show its duration
# Indicators: short flags from your own functions (docs/prompt.md)
om818_prompt_indicators=()
typeset -gA om818_prompt_indicator_colors=() # e.g. om818_prompt_indicator_colors[todo]=red
# Git
# Folders without git status: patterns matched against the whole current folder, quoted
# (unquoted, zsh fails when they match no file), e.g. ('/mnt/*' '~/big-repo*')
om818_prompt_git_ignore=()
om818_prompt_git_max_count=99 # larger counts show as 99+
# Above this many files, only staged changes count (-1: no limit)
om818_prompt_git_max_index_size=-1
om818_prompt_git_count_untracked=on # off: faster in huge repositories
# Seconds to wait for git before showing the prompt; empty: 0.02 in zsh (it redraws when git
# answers), 0.5 in bash
om818_prompt_git_timeout=

# The look: colors and symbols, as tables. Change one key (om818_prompt_colors[path]=33):
# assigning a whole table replaces all its keys.
# Basic mode, for terminals with few colors or no Unicode, uses the *_basic tables (a key missing
# there comes from the main table): on, off, or auto (the Linux console, a locale not UTF-8)
om818_prompt_basic=auto

# Colors: a name (black red green yellow blue magenta cyan white, or default: the terminal's text
# color), a 256-color number (202) or #rrggbb, optionally after bold or underline ('bold 202').
# Pastel colors with a meaning for git: lavender branch, mint staged, sand changed, coral
# conflicts, sky ahead/behind, grey untracked, stashes and brackets.
typeset -gA om818_prompt_colors=(
  [user]='bold 202'
  [host]='bold 202'
  [root]=red
  [path]=178
  [date]=8
  [ok]=green
  [err]=red
  [env]=cyan # the environments you are in (each can have its own: [env_drop]=…, [env_venv]=…)
  [duration]=yellow
  [jobs]=yellow
  [indicator]=168
  [indicator_bracket]=240
  [git_bracket]=240
  [git_branch]=141
  [git_action]=180 # merge, rebase…
  [git_remote]=110 # ahead and behind
  [git_no_upstream]=240
  [git_staged]=114
  [git_conflicts]='bold 203'
  [git_changed]=179
  [git_untracked]=244
  [git_stashes]=244
  [git_unknown]=179 # repository too big to scan (om818_prompt_git_max_index_size)
  [git_clean]=114
)
# Basic mode: 8 colors
typeset -gA om818_prompt_colors_basic=(
  [user]='bold yellow'
  [host]='bold yellow'
  [path]=yellow
  [date]=default
  [indicator]=magenta
  [indicator_bracket]=default
  [git_bracket]=default
  [git_branch]=magenta
  [git_action]=yellow
  [git_remote]=cyan
  [git_no_upstream]=default
  [git_staged]=green
  [git_conflicts]='bold red'
  [git_changed]=yellow
  [git_untracked]=default
  [git_stashes]=default
  [git_unknown]=yellow
  [git_clean]=green
)

# Symbols, and the texts around segments
typeset -gA om818_prompt_symbols=(
  [user]='$'
  [root]='#'
  [host_separator]='@'
  [ok]='✔'
  [err]='✘' # followed by the failed status: ✘1, ✘1|0 (a pipeline), ✘INT (a signal)
  [jobs]='⚙'
  [env_prefix]='('
  [env_suffix]=')'
  [env_separator]=' '
  [path_ellipsis]='…' # what stands for the folders not shown (om818_prompt_path_depth)
  [indicator_prefix]='{'
  [indicator_suffix]='}'
  [git_prefix]='['
  [git_suffix]=']'
  [git_separator]='|'
  [git_behind]='↓'
  [git_ahead]='↑'
  [git_push_behind]='⇠'
  [git_push_ahead]='⇢'
  [git_no_upstream]='∅'
  [git_staged]='●'
  [git_conflicts]='✖'
  [git_changed]='✚'
  [git_untracked]='…'
  [git_stashes]='≡'
  [git_unknown]='?'
  [git_clean]='✔'
)
# Basic mode: ASCII symbols
typeset -gA om818_prompt_symbols_basic=(
  [ok]='+'
  [err]='x'
  [jobs]='&'
  [path_ellipsis]='...'
  [git_behind]='v'
  [git_ahead]='^'
  [git_push_behind]='<'
  [git_push_ahead]='>'
  [git_no_upstream]='-'
  [git_staged]='*'
  [git_conflicts]='!'
  [git_changed]='+'
  [git_untracked]='?'
  [git_stashes]='='
  [git_unknown]='~'
  [git_clean]='.'
)
