# With chezmoi

Keep oh-my-818 in your [chezmoi](https://www.chezmoi.io) dotfiles: a new machine gets it, with
your settings, at its first `chezmoi apply`.

## The setup

In your chezmoi source (`chezmoi cd`):

```
dot_config/private_om818/              ~/.config/om818 (private): config.sh, env.d/, shell.d/
run_onchange_after_install-om818.sh    installs oh-my-818, once per machine
```

```sh
#!/bin/sh
# run_onchange_after_install-om818.sh: installs oh-my-818 when missing
set -eu
if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/om818/.git" ]; then exit 0; fi
# Downloaded first, so that a failed download fails the script
script="$(curl -fsSL https://raw.githubusercontent.com/nathan818fr/oh-my-818/main/install.sh)"
sh -c "$script"
```

`chezmoi apply` writes your files, then runs the script once per machine (again only when you
change it), which installs oh-my-818 when it's missing: an `om818 uninstall` stays done. Add your
files one by one (`chezmoi add ~/.config/om818/config.sh`) rather than the
whole folder, so that per-machine and secret files stay out. On a machine that already has
`~/.config/om818`, run `chezmoi diff` first: apply replaces those files without asking.

## Your startup files

The installer adds its lines to `~/.zshenv`, `~/.bashrc`, `~/.profile`… If chezmoi manages
some of them (`chezmoi managed` lists them), do this after the first apply, before the next
one: an apply that overwrites them removes oh-my-818 from your shells. Either:

- stop managing them, after moving your own lines to `env.d/` and `shell.d/`:
  `chezmoi forget ~/.zshenv ~/.bashrc ~/.profile`;
- or keep them, with the installer's lines: `chezmoi re-add ~/.zshenv ~/.bashrc ~/.profile`.
  For a template, copy the `# om818` lines in with `chezmoi edit`, at the same place (in
  `~/.bashrc`, the environment line first, the oh-my-818 line last).

In both commands, list only the files chezmoi manages: one it doesn't makes the whole command
fail.

`chezmoi status` then lists none of them. With `om818_protect_startup_files=on`, give them
chezmoi's `readonly_` attribute (`readonly_dot_bashrc`) and keep `~/.zshrc` as
`readonly_empty_dot_zshrc`, else each apply and each install undo each other.

A `~/.zshrc` in chezmoi is no longer read: copy its content to `shell.d/`, then `chezmoi forget
~/.zshrc` (or keep it empty, as above).

## Tips

- Secrets from a password manager, quoted for sh:

  ```
  # dot_config/private_om818/env.d/private_secrets.sh.tmpl
  export GITHUB_TOKEN={{ onepasswordRead "op://Private/GitHub/token" | shellQuote }}
  ```

- To skip the install on some machine, make the script a template
  (`run_onchange_after_install-om818.sh.tmpl`) and wrap its content in `{{ if … }}…{{ end }}`.
- `om818_update=auto` in your `config.sh` keeps every machine up to date by itself.

## To stop using it

On each machine, run `om818 uninstall` first: once an apply has removed the `# om818` lines,
the `om818` command is gone (it is still `~/.local/share/om818/bin/om818`). Then remove the
script and `dot_config/private_om818` from your source, the `# om818` lines from the startup files
it manages, and their `readonly_` attribute if you added it.
