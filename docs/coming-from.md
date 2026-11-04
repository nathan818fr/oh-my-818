# Coming from…

How to move your setup from oh-my-zsh, a `.bashrc`, dotfiles or a zsh plugin manager.

## oh-my-zsh

The installer leaves `~/.zshrc` and `~/.oh-my-zsh` in place, but zsh stops reading `~/.zshrc`.
Before installing, close your other terminals (your history is copied once), and keep a list of
oh-my-zsh's aliases to pick from: `alias > ~/old-aliases.txt`. Then, before opening a new
terminal, copy your own lines from `~/.zshrc`:

- aliases, functions → `~/.config/om818/shell.d/` (a `.sh` file is read by both shells);
  `setopt`, `bindkey` → a `.zsh` file there (zsh only);
- `export` lines → `~/.config/om818/env.d/`; PATH changes too, written with
  `om818_path_prepend` ([Variables and PATH](customize.md#variables-and-path-envd));
- tool blocks (`nvm`, `conda initialize`…) → `~/.config/zsh/.zshrc`, below its `# om818` line;
- oh-my-zsh's own lines (`ZSH=`, `plugins=(…)`, `source $ZSH/oh-my-zsh.sh`) → leave them: two
  setups at once break each other.

Then set the whole file aside: `mv ~/.zshrc ~/.zshrc.pre-om818`. `om818 uninstall` puts it back as
it was, oh-my-zsh included. If `~/.zshrc` comes back later (a tool's installer), `om818 status`
says what to do: don't set it aside a second time, that would replace your copy.

Plugins: direnv, fzf, zoxide… are [integrations](integrations.md); turn fzf and zoxide on.
Others, like zsh-autosuggestions and zsh-syntax-highlighting, load from `shell.d/`, in a file
whose name sorts last:

```zsh
# shell.d/zz-plugins.zsh
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

(Those paths are your distribution's packages; plugins cloned into `~/.oh-my-zsh/custom/plugins`
work too, but move them out first if you'll delete `~/.oh-my-zsh`.)

To keep powerlevel10k: set `om818_theme=off` in `config.sh`, put its instant-prompt block at the
top of `~/.config/zsh/.zshrc`, and load powerlevel10k from `shell.d/` (with your `~/.p10k.zsh`).

oh-my-zsh's aliases (`ll`, `gst`…) and options (`auto_cd`…) aren't set: add back those you use in
`shell.d/`.

`omz update` becomes `om818 update`, `omz reload` becomes `exec zsh`.

## Your own `.bashrc`

bash still reads all of `~/.bashrc`, then oh-my-818 at its end: your aliases and PATH changes
keep working, but oh-my-818's prompt, history and keys replace yours. To keep yours:
`om818_theme=off`, `om818_history=off` or `om818_keys=off`. Moving lines to `env.d/` and
`shell.d/` is optional (it shares them with zsh).

## Dotfiles

Keep `~/.config/om818/` in your dotfiles, and run the installer when oh-my-818 is missing: see
[With chezmoi](chezmoi.md) (the same script works from yadm's bootstrap or your own).

If your dotfiles manage the startup files (`~/.bashrc`, `~/.zshenv`…), the installer's lines land
in them: commit those lines, or let oh-my-818 own those files.

## A zsh plugin manager

oh-my-818 can load as a zsh plugin (`om818.plugin.zsh`), but then only interactive zsh gets it:
no bash, no environment for other programs, no git status in the prompt. The installer is the
full setup.
