# Customize

Your files are in `~/.config/om818/`:

```
~/.config/om818/
├── config.sh      your settings (create it when you need it)
├── env.d/         your variables and PATH: *.sh
└── shell.d/       your aliases, functions, key bindings: *.sh (zsh and bash), *.zsh, *.bash
```

Create files with any editor (`nano ~/.config/om818/shell.d/aliases.sh`). They load in name
order, and changes apply to new terminals (or `exec zsh`, `exec bash` in the current one).

## Aliases, functions, key bindings: `shell.d/`

Loaded by interactive shells, after oh-my-818. A `.sh` file is loaded by both zsh and bash, so it
must work in both; a `.zsh` or `.bash` file by that shell only.

```sh
# shell.d/aliases.sh
alias ll='ls -lah'
mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
```

```zsh
# shell.d/keys.zsh
bindkey '^U' backward-kill-line   # Ctrl+U deletes up to the cursor
```

bash still reads your `~/.bashrc`, so the aliases there keep working.

## Variables and PATH: `env.d/`

Loaded first, in every shell and login session, so every program you start gets these variables
(on Linux, desktop apps too, after logging in again). Plain sh only: `sh` reads them too.
`~/.local/bin` and `~/bin` are already in front of PATH.

```sh
# env.d/10-env.sh
export EDITOR=nano
om818_path_prepend "$HOME/.npm-global/bin" # in front of PATH, unless already there
om818_path_append /opt/tool/bin            # at the end of PATH, unless already there
om818_path_first "$HOME/wrappers"          # first on PATH, kept first even ahead of mise
```

Keep secrets in a file of their own (`env.d/secrets.sh`, `chmod 600`), out of your dotfiles.

## Settings: `config.sh`

[`defaults.sh`](../defaults.sh) lists every setting with its default. Copy the lines you want to
change into `config.sh`:

```sh
# config.sh
om818_prompt_date_tz=UTC
om818_fzf=on
om818_prompt_colors[path]=33   # a table: set one key, not the whole table
```

After a change, the next new terminal reports unknown settings and invalid values once;
`om818 status` reports them too.

`config.sh` is shell code, so conditions work, e.g. per machine:

```sh
# config.sh
if [ "${HOST:-$HOSTNAME}" = laptop ]; then om818_theme=off; fi
```

## Commands only in a sandbox

To keep a command, e.g. an AI agent, from running outside a sandbox:

```sh
# config.sh
om818_sandbox_only=(claude codex)
om818_sandboxes=(drop container)   # the default
```

[drop](https://github.com/wrr/drop) is a sandbox tool. `container` means a podman or docker
container (or another that sets `$container`). toolbox and distrobox don't count unless you add
`toolbox` or `distrobox`: they share your whole home folder. `chroot` and `flatpak` are also
possible.

Outside a sandbox, `claude` then stops with a hint, whoever runs it: your terminals, scripts, and
IDEs started from your Linux desktop (after logging in again), since they find it on PATH. Inside
one, it runs as usual. `OM818_SANDBOX_ONLY=off claude` runs it anyway.

It's a reminder, not isolation: a program calling the command by its full path, or a macOS app
started from the Dock, doesn't go through it. A sandbox started from your terminal gets your
`env.d/` variables (secrets included) in its environment, unless it clears it. One that mounts
`~/.config/om818`, `~/.local/share/om818`, `~/.local/state/om818` or `~/.cache/om818` can run
code on your machine at your next terminal: mount them read-only (your history files too, to
keep them as they are).

## Protecting your startup files

Tool installers (nvm, conda, rustup…) like to add lines to `~/.bashrc` or `~/.profile`. To stop
them:

```sh
# config.sh
om818_protect_startup_files=on
```

Then run `om818 install`: it makes the startup files read-only (and creates empty read-only ones
where installers might write, like `~/.zshrc`). Such an installer then fails or warns; add what
it needed yourself, in `env.d/` or `shell.d/`. To edit a protected file: `chmod u+w`, edit, then
`om818 install`. Setting it back to `off`, then `om818 install`, undoes it.
