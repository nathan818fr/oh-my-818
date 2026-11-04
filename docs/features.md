# What you get

Besides [the prompt](prompt.md), in zsh and bash. Each feature can be turned off in
[`config.sh`](customize.md#settings-configsh).

## History

- Up and Down search the history for what you typed: type `git`, press Up, get the last `git`
  command. On an empty line, they work as usual.
- Each command is saved as soon as it runs (20000 commands), in `~/.local/state/zsh/history` and
  `~/.local/state/bash/history`, as the Arch wiki's XDG page suggests. Tools reading it (e.g.
  `atuin import zsh`) look for `~/.zsh_history` unless you give them `HISTFILE`.
- A command starting with a space isn't saved.
- `!!` and `!$` are shown before they run.

`om818_history_share=on` shares commands between open zsh terminals at once. bash has no exact
way; [atuin](https://atuin.sh) does it for both shells. `om818_history=off` keeps the shell's own
history.

## Keys

| Keys                  | What they do                                         |
| --------------------- | ---------------------------------------------------- |
| Up, Down              | previous or next command starting with what is typed |
| Ctrl+Left, Ctrl+Right | move by word (macOS: Option+Left, Option+Right)      |
| Ctrl+Delete           | delete the next word                                 |
| Home, End             | start or end of the line                             |
| Ctrl+X Ctrl+E         | edit the command in your editor                      |

zsh gets emacs keys, as with oh-my-zsh, whatever `EDITOR` is: for vi keys, `bindkey -v` in a
`shell.d/` file. `om818_keys=off` keeps the shell's own keys.

## Completion

Tab completes ignoring case, and lists the choices at once (zsh: in a menu). zsh gets extra
completions from [zsh-completions](https://github.com/zsh-users/zsh-completions); some tools'
completions are [generated](integrations.md#tool_completions). `om818_completion=off` keeps the
shell's own.

## Terminal title

The command running, else the current folder (with the host over SSH). `om818_title=off`.

## Clipboard

```sh
pwd | clipcopy        # copy a command's output
clippaste > notes.txt # paste
```

They use macOS's, Windows' (WSL), Wayland's (`wl-clipboard`) or X11's (`xclip`, `xsel`)
clipboard, else tmux's buffer (e.g. over SSH). `om818_clipboard=off`.

## What it doesn't do

- It isn't a plugin manager: load other zsh plugins from `shell.d/`
  ([Coming from oh-my-zsh](coming-from.md#oh-my-zsh)).
- It doesn't add oh-my-zsh's aliases (`ll`, `gst`…).
- It doesn't support fish, or bash older than 4.4 (macOS's `/bin/bash`).
