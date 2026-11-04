# Integrations

oh-my-818 sets up these tools when they are installed. Each has a setting, `om818_<name>`:
`auto` (on when the tool is found), `on` or `off`. Those that replace something you know (a
key, a command, the prompt) are off until you turn them on. `om818 status` shows each one and why.

| Integration        | Default | What it does                                                    |
| ------------------ | ------- | --------------------------------------------------------------- |
| `mise`             | auto    | activates mise, and puts its shims on PATH                      |
| `podman`           | auto    | Docker clients use podman (Linux, without Docker)               |
| `homebrew`         | auto    | Homebrew's commands on PATH, its zsh completions                |
| `direnv`           | auto    | loads each folder's `.envrc`                                    |
| `gpg`              | auto    | `GPG_TTY`, for passphrase prompts                               |
| `1password`        | auto    | 1Password CLI shell plugins                                     |
| `tool_completions` | auto    | completions generated for tools shipping none                   |
| `xdg`              | auto    | tools' files in `~/.local/share`… instead of hidden folders     |
| `fzf`              | off     | fuzzy Ctrl+R (history), Ctrl+T (files), Alt+C (folders)         |
| `zoxide`           | off     | `z <part of a path>` jumps to a folder you often visit          |
| `starship`         | off     | [starship](https://starship.rs)'s prompt instead of oh-my-818's |

**After installing a tool, run `om818 env`**, then open a new terminal.

A tool not listed: put its `eval "$(tool init zsh)"` line in a `shell.d/` file.

## mise

`mise activate` in your shells; its shims on PATH for scripts, IDEs and desktop apps.

## podman

Points `DOCKER_HOST` to podman's socket, unless a real Docker is there or you set `DOCKER_HOST`
yourself. Enable the socket with `systemctl --user enable --now podman.socket`. With Docker
Desktop, set `om818_podman=off`.

## homebrew

Like `brew shellenv`, plus its tools' zsh completions: no need for Homebrew's line in
`~/.zprofile`. bash's completions need `brew install bash-completion@2`. A Homebrew installed by
another account (a shared Mac) is left out: its commands could run code as you.

## tool_completions

Generates completions for gh, rg, fd, uv, rustup, cargo, mise, podman, docker, kubectl, helm,
just, deno… ([the list](../integrations/tool_completions/tools.list)) when their package ships
none.

## xdg

These tools keep their files out of your home folder:

| Tool   | Variable           | Folder                  |
| ------ | ------------------ | ----------------------- |
| cargo  | `CARGO_HOME`       | `~/.local/share/cargo`  |
| rustup | `RUSTUP_HOME`      | `~/.local/share/rustup` |
| go     | `GOPATH`           | `~/.local/share/go`     |
| gradle | `GRADLE_USER_HOME` | `~/.local/share/gradle` |
| npm    | `npm_config_cache` | `~/.cache/npm`          |
| docker | `DOCKER_CONFIG`    | `~/.config/docker`      |

A tool you already use (its old folder exists) stays where it is; `om818 status` shows how to
move it. A variable you set yourself (e.g. `GOPATH` in `~/.profile` or `env.d/`) wins; also set
`om818_xdg_go=off` then, else `~/.local/share/go/bin` stays on PATH. Go's
module cache goes to `~/.cache/go/mod`; on macOS, docker keeps `~/.docker` (Docker Desktop), and
zsh no longer writes `~/.zsh_sessions` (`om818_xdg_zsh_sessions=off` keeps it).
`om818_xdg_<tool>=off` leaves one tool alone.

## fzf

Needs fzf 0.48 or newer (Debian 12 and Ubuntu 24.04 ship older ones).
