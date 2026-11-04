# Troubleshooting

What to check when something goes wrong, and notes per system.

## First: `om818 status`

It shows what is set up: versions, startup files, settings, each integration and why it is on or
off. Rows marked `!` need action and say how. Share it when asking for help
([open an issue](https://github.com/nathan818fr/oh-my-818/issues)), after reading it: it shows
your home folder as `~` and leaves out most settings, but it does show some of your setup (tool
paths, `TERM` and `LANG`, the start of a tool's error).

To check whether oh-my-818 causes a problem, start a shell without it: `zsh -f` or `bash --norc`
(`exit` to come back).

## Common problems

- **`om818: command not found` right after installing:** open a new terminal.
- **My aliases stopped working (zsh):** zsh no longer reads `~/.zshrc`
  ([zsh's files move](install.md#zshs-files-move-to-configzsh)); copy them to `shell.d/`.
- **Up doesn't show the previous command:** it shows the last one starting with what you typed.
  On an empty line it works as usual; `om818_keys=off` restores the shell's keys.
- **Errors when a terminal opens:** the message names the file and line; fix it, or move the file
  out of `shell.d/`.
- **A setting has no effect:** it applies to new terminals. `om818 status` reports unknown setting
  names and invalid values; new terminals warn about unknown table keys and prompt segments.
- **A tool I installed isn't set up:** `om818 env`, then a new terminal.
- **Odd symbols in the prompt:** try another font, or `om818_prompt_basic=on`.
- **No git status in the prompt:** gitstatusd wasn't downloaded (offline at install time): run
  `om818 install`.
- **zsh installed, or login shell changed, after oh-my-818:** `om818 install` in a new terminal.
- **A tutorial mentions `~/.cargo` or `~/go`:** the `xdg` integration put them in
  `~/.local/share/` ([xdg](integrations.md#xdg)).
- **A variable I removed from `env.d/` is still set:** terminals inherit it from your session;
  log out and back in.

## Per system

### Before installing

| System         | Install first                                             |
| -------------- | --------------------------------------------------------- |
| Ubuntu, Debian | `sudo apt install git curl` (and `zsh` if you want it)    |
| Fedora         | `sudo dnf install git` (and `zsh`)                        |
| Arch           | `sudo pacman -S git curl` (and `zsh`)                     |
| macOS          | `xcode-select --install` (git); zsh is the default        |
| Alpine         | `apk add git curl bash bash-completion shadow`, see below |

### macOS

- `/bin/bash` is too old (3.2): only zsh gets the setup. For a newer bash:
  `brew install bash bash-completion@2`, add `$(brew --prefix)/bin/bash` to `/etc/shells`, make
  it your shell (`chsh -s`), then `om818 install`.
- Homebrew's `brew shellenv` line in `~/.zprofile` isn't needed: run `om818 env` after
  installing Homebrew.
- Apps started from the Dock don't get your `env.d/` variables.
- Use Option+Left and Option+Right to move by word (Ctrl+arrows switch Spaces).

### WSL

- Windows' folders on PATH make command lookups slow: `appendWindowsPath=false` in
  `/etc/wsl.conf` (`[interop]`), then `wsl --shutdown`.
- Git status on Windows drives is slow: `om818_prompt_git_ignore=('/mnt/[a-z]' '/mnt/[a-z]/*')`.
- With Docker Desktop: `om818_podman=off`.

### Linux servers

- Each user installs for themselves, root too (`sudo -i` first, not `sudo` in front of the
  install line).
- `om818_update=auto` keeps a server up to date by itself.
- Alpine: after `chsh -s /bin/bash`, log out and back in before installing.
- Over SSH, a server missing your locale shows plain symbols (basic mode); `su - user` hides the
  host from the prompt (`om818_prompt_host=on` in that user's `config.sh`).
- NixOS runs zsh's compinit in `/etc/zshrc` too (twice the cost): set
  `programs.zsh.enableGlobalCompInit = false`.

### Limits

oh-my-818 is made for the systems above. These setups work, but their corner cases aren't handled
(`om818 install` repairs most of them):

- Nix, Guix and home-manager: a tool's cached setup may go stale after a garbage collection, and a
  `config.sh` linked from the store isn't noticed when it changes (run `om818 env`).
- busybox as your everyday system, and a home folder shared over NFS by different systems.
- Sandboxes and nested namespaces around a temporary install: their shells may not count.
- A history file of your own (`HISTFILE` in your startup files): it isn't copied, and stays as
  it is when you uninstall.
