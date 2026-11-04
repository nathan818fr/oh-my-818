# oh-my-818

[![CI](https://github.com/nathan818fr/oh-my-818/actions/workflows/ci.yml/badge.svg)](https://github.com/nathan818fr/oh-my-818/actions/workflows/ci.yml)

A ready-to-use setup for zsh and bash:

- a clear prompt with git status ([what each part means](docs/prompt.md));
- a better history, keys and completion ([what you get](docs/features.md));
- your aliases and variables in plain files, for both shells;
- your tools set up when you have them: mise, Homebrew, direnv, podman, and fzf or zoxide when
  you turn them on
  ([integrations](docs/integrations.md)).

Linux first, also macOS and WSL.

![A terminal session: the prompt in the home folder, then in a git repository with its status,
in a drop sandbox, after a failed cargo test](.github/prompt.png)

## Install

You need git 2.17+ and curl, and zsh 5.1+ or bash 4.4+
([per system](docs/troubleshooting.md#per-system)).
Then, as yourself (not with sudo):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)"
```

and open a new terminal. Over SSH (a server, a VM), the line below also restarts your shell with
oh-my-818, so you can stay connected; it is safe to run again (it repairs, or changes nothing):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)" && exec "$SHELL" -l
```

The installer adds a few lines, marked `# om818`, to your startup files (`~/.bashrc`,
`~/.profile`, `~/.zshenv`) and copies your history. **zsh users:** zsh then reads
`~/.config/zsh/.zshrc` instead of `~/.zshrc`, so copy your aliases and other lines
([Coming from…](docs/coming-from.md)). Details, updates and `om818 uninstall`:
[Install, update, uninstall](docs/install.md).

For a one-time session on someone else's machine, `-- --temp` makes a temporary install instead.
It changes none of the startup files: it lives in a folder of its own, removed once you exit,
and only your commands stay, in the usual history
([details and limits](docs/install.md#temporary-install)):

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)" -- --temp
```

## Use

Your files go in `~/.config/om818/` ([Customize](docs/customize.md)):

```sh
# shell.d/aliases.sh: aliases and functions
alias ll='ls -lah'
```

```sh
# env.d/10-env.sh: variables and PATH
export EDITOR=nano
om818_path_prepend "$HOME/.npm-global/bin"
```

```sh
# config.sh: settings, copied from defaults.sh
om818_prompt_colors[user]=green
```

Changes apply to new terminals.

```
om818 status      what is set up, and what to fix
om818 update      update to the latest release
om818 help        the other commands
```

## Documentation

[What you get](docs/features.md) · [The prompt](docs/prompt.md) ·
[Customize](docs/customize.md) · [Integrations](docs/integrations.md) ·
[Coming from…](docs/coming-from.md) · [With chezmoi](docs/chezmoi.md) ·
[Install, update, uninstall](docs/install.md) · [Troubleshooting](docs/troubleshooting.md) ·
[All the settings](defaults.sh) · [Contributing](CONTRIBUTING.md)

Something wrong? `om818 status`, then
[open an issue](https://github.com/nathan818fr/oh-my-818/issues) with its output.

## License

MIT. The code in `vendor/` keeps its own license (each folder has it): zsh-defer and gitstatus
are GPL-3.0; ez-compinit, oh-my-zsh and bash-preexec are MIT; zsh-completions has its own terms.
