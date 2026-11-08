# The prompt

What each part of the prompt means, and how to change it.

```
✔ 3s (drop:dev venv:api) nat ~/Repo/api [main↑1|●1✚2…3] {todo}
12:34 ⚙1 $
```

| Part                  | Meaning                                                  | Color key      |
| --------------------- | -------------------------------------------------------- | -------------- |
| `✔` / `✘1`            | the last command succeeded / failed, with its exit code  | `ok`, `err`    |
| `3s`                  | how long it took, from 3 s up                            | `duration`     |
| `(drop:dev venv:api)` | the [environments](#environments) you're in              | `env`          |
| `nat`                 | the user; `@host` is added over SSH, as root, under sudo | `user`, `root` |
| `~/Repo/api`          | the current folder                                       | `path`         |
| `[main↑1\|●1✚2…3]`    | [git](#git): the branch, then the changes                | `git_*`        |
| `{todo}`              | your [indicators](#indicators)                           | `indicator`    |
| `12:34`               | the clock                                                | `date`         |
| `⚙1`                  | background jobs, when there are some                     | `jobs`         |
| `$`                   | `#` as root                                              |                |

A failed pipeline shows each command's code (`✘1|0`); a command stopped by Ctrl+C shows `✘INT`.

The settings are the `om818_prompt_*` lines of [`defaults.sh`](../defaults.sh).

## Lines

Each line lists its segments, in order: line 1 is
`status duration env user path git indicators`, line 2 `date jobs symbol`. The last command's
result comes first, where your eyes land after its output; then where you are.

```sh
# config.sh
om818_prompt_line2=(jobs symbol)   # no clock
```

```sh
# config.sh
om818_prompt_line1=(path git symbol)   # a one-line prompt
om818_prompt_line2=()
```

Other settings: `om818_prompt_path_depth` (folders shown), `om818_prompt_date_format` and
`om818_prompt_date_tz` (the clock), `om818_prompt_host` (`auto`, `on`, `off`),
`om818_prompt_default_user` (a user name to hide).

## Environments

Shown when active: [drop](https://github.com/wrr/drop) sandboxes, containers, chroots, SSH,
flatpak, nix, flox, Python virtualenvs and conda (`om818_prompt_envs`).

## Git

| Before `\|` | Meaning                                   |
| ----------- | ----------------------------------------- |
| `main`      | the branch (else the tag, else `@commit`) |
| `:rebase`   | an action in progress (rebase, merge…)    |
| `↑1` / `↓1` | commits ahead of / behind the upstream    |
| `⇢1` / `⇠1` | the same, for the push remote (forks)     |
| `∅`         | no upstream                               |
| `≡1`        | stashes                                   |

| After `\|` | Meaning         |
| ---------- | --------------- |
| `●1`       | staged files    |
| `✖1`       | conflicts       |
| `✚1`       | changed files   |
| `…1`       | untracked files |
| `✔`        | clean           |
| `?`        | too big to tell |

Git status comes from gitstatusd, which stays fast in big repositories. For huge ones, or folders
where you don't want it:

```sh
# config.sh
om818_prompt_git_count_untracked=off
om818_prompt_git_ignore=('/mnt/*' '~/big-repo*')   # quoted patterns
```

`om818_prompt_git=off` turns git status off: the git segment stays empty, and `om818 install`
no longer downloads gitstatusd.

## Colors and symbols

Change one key of a table; the others keep their default:

```sh
# config.sh
om818_prompt_colors[path]=33              # a 256-color number
om818_prompt_colors[user]='bold #ff8700'  # or #rrggbb, or a name (red, cyan…)
om818_prompt_symbols[ok]='✓'
```

On terminals without Unicode or colors (the Linux console, a non-UTF-8 locale), the prompt uses
ASCII symbols and 8 colors. `om818_prompt_basic` sets it: `auto`, `on` or `off`.

## Indicators

Short flags of your own, from a function in a `shell.d/` file that sets `REPLY`:

```sh
# shell.d/todo.sh
function om818_indicator_todo() { if [[ -e ./TODO ]]; then REPLY='todo'; fi; }
om818_prompt_indicators+=(todo)
```

It runs before each prompt: keep it fast.

## Another prompt

- [starship](https://starship.rs): `om818_starship=on`.
- Your own (a `PS1`, powerlevel10k…): `om818_theme=off`, then set it in `shell.d/`.

With either one, `om818 install` no longer downloads gitstatusd.
