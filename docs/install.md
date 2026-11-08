# Install, update, uninstall

What the installer changes, the temporary install, updates, and going back.

## What the installer changes

It adds lines marked `# om818` to your shell's startup files:

- `~/.zshenv` (with zsh): sets `ZDOTDIR=~/.config/zsh`, loads the environment;
- `~/.config/zsh/.zshrc` (with zsh): loads oh-my-818;
- `~/.bashrc`: loads the environment (first line, so that `ssh host cmd` gets it), then
  oh-my-818 (last line);
- `~/.profile`, and `~/.bash_profile` or `~/.bash_login` if you have one: loads the environment;
  when bash is your login shell, also `~/.bashrc`, unless the file already does.

A file that already loads oh-my-818 (e.g. from your dotfiles) is left alone, and so is a
read-only one: the installer prints the line to add. `om818 install` adds lines that went
missing.

It also copies your history (`~/.zsh_history`, `~/.bash_history`) to
`~/.local/state/zsh/history` and `~/.local/state/bash/history` (where the Arch wiki's XDG page
puts them). A history file your startup files set with `HISTFILE` (e.g. `~/.histfile`) isn't
copied: the installer names the startup file, with the command to copy it. It also downloads
gitstatusd, the helper behind the prompt's git status, unless nothing uses it
([git status](prompt.md#git)). The commands of the terminal running the installer are saved by
its shell when it exits or restarts, after that copy: they stay in `~/.bash_history` (or
`~/.zsh_history`) only.

### zsh's files move to `~/.config/zsh`

zsh reads its files from the folder in `ZDOTDIR`, keeping their names: `~/.config/zsh/.zshrc`
(with the dot), no longer `~/.zshrc`. A `ZDOTDIR` you already set is kept. Your `~/.zshrc` stays
as it is but isn't read: copy what you need ([Coming from…](coming-from.md)), then set it aside
as `~/.zshrc.pre-om818`, which `om818 uninstall` puts back. The installer says so (without a
terminal, the first zsh does), and new terminals again when a tool's installer adds lines to it.

bash has no such setting: it always reads `~/.bashrc` from your home folder, so nothing moves.

### The environment

The environment is oh-my-818's variables (PATH, tools' folders…) in one generated file,
`~/.local/state/om818/env.sh`, which then loads your `env.d/` files; the startup files load it.
It is generated again by updates, and by a new terminal when `config.sh` changed. After
installing a tool with an [integration](integrations.md), run `om818 env`.

### Folders

| Folder                  | What's in it                                          |
| ----------------------- | ----------------------------------------------------- |
| `~/.config/om818/`      | your files: `config.sh`, `env.d/`, `shell.d/`         |
| `~/.local/share/om818/` | oh-my-818 itself (a git checkout)                     |
| `~/.local/state/om818/` | the environment, the update check                     |
| `~/.cache/om818/`       | gitstatusd, generated completions, cached tool output |

They follow `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `XDG_CACHE_HOME` when set.

## Temporary install

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)" -- --temp
```

It installs the latest release into a private folder (`$XDG_RUNTIME_DIR/om818-temp`, else
`~/.cache/om818-temp-<host>`; in a container, with a suffix of its own) and starts a shell on
it: your login shell if it is zsh or bash 4.4+, else zsh, else bash. That shell reads
oh-my-818's defaults only (not the machine's `~/.zshrc` or `~/.bashrc`), has no git status in its
prompt, and no updates. Apart from that folder, oh-my-818 leaves nothing in your home folder but
your commands, added to the history file your shells use (`~/.zsh_history` or `~/.bash_history`,
or oh-my-818's own when the account has it; not one the account's startup files set, like
`~/.histfile`). Tools it activates, like mise, may keep their own files.

Another session running the same line shares the install, and so do the shells started from it
(`bash`, `$SHELL`, tmux's, and `zsh` from a zsh session). The folder is removed when the last of these shells exits or
loses its connection; `exit` brings you back to the shell you started from. A shell killed
(`kill -9`) or replaced by `exec bash` (use `exec "$SHELL"` instead) leaves the folder until the
next temporary session, or your logout for `$XDG_RUNTIME_DIR`.

## Updates

Once a day, a new terminal checks for a release in the background, and prints one line when
there is one. `om818 update` installs it and shows what changed ([CHANGELOG](../CHANGELOG.md)).
With `om818_update=auto` in `config.sh`, new terminals update by themselves; `off` stops the
check.

`om818 rollback` goes back to the previous release. If an update breaks your shell, open one
without it (`zsh -f` or `bash --norc`) and run `~/.local/share/om818/bin/om818 rollback`.

oh-my-818 is young: a release may still change settings. The changelog says what to do, and new
terminals report settings that no longer exist.

To install a given release: `OM818_REF=v0.1.0` in front of the install line. From a copy or a
mirror: `OM818_REPO=<url or folder>`.

## Uninstall

```sh
om818 uninstall
```

It removes its lines from your startup files (and the files it created), and removes
`~/.local/share/om818` and its state and cache. Your files in `~/.config/om818` stay. It lists
what's left for you, e.g. what you added to `~/.config/zsh/.zshrc`, or a tool folder to move back
(`mv ~/.local/share/cargo ~/.cargo`). Your history, in `~/.local/state/`, moves back to
`~/.zsh_history` or `~/.bash_history` if that file is gone; else it stays, and the command to use
it is shown (when your startup files set `HISTFILE`, where it is).

Close your other terminals first (they keep oh-my-818 until closed), then open a new one (over
SSH, log out and connect again; on a Linux desktop, log out and back in). After installing it again, move tool blocks (nvm…) back
below the `# om818` line of `~/.config/zsh/.zshrc`.
