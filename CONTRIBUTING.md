# Contributing

This is a personal project: a pull request may not be reviewed or merged.

## Setup

You need git, zsh, bash 4.4+ (macOS: `brew install bash`), tmux (for the terminal tests, skipped
without it) and [mise](https://mise.jdx.dev), which installs the other tools (`.config/mise.toml`,
after `mise trust` in the repository).

```
mise run lint            shellcheck, shfmt, zsh -n, 100 columns, docs links and examples
mise run fmt             format in place
mise run test            the tests, each in a throwaway HOME
mise run vendor-update   refresh vendor/ from vendor/sources.txt
```

One test file: `tests/run tests/test-prompt.sh`; one test: `bash tests/test-prompt.sh test_colors`.
Run one suite at a time: each starts many shells. CI runs the lint, and the tests on Ubuntu,
macOS and bash 4.4 (Alpine). A change that only touches docs runs just the lint.

A pull request: lint and tests pass, plus a line in `CHANGELOG.md` under `## Unreleased` when
users notice the change.

## Layout

```
install.sh            runs from main: clones, checks out the latest release
bin/om818, lib/       the om818 command: install, update, status, uninstall…
defaults.sh           every setting, with its default
modules/env/          generates the environment (~/.local/state/om818/env.sh)
modules/shell/        interactive zsh and bash: shared code, the prompt theme
modules/zsh/, bash/   what differs per shell
integrations/<name>/  one folder per tool (contract at the top of lib/integrations.sh)
vendor/               third-party code, never edited by hand
tests/                tests/lib.sh explains the sandbox
```

Three kinds of shell code:

- POSIX sh (plus `local`): `install.sh`, `bin/om818`, `lib/`, `modules/env/`, each
  `integration.sh`. They run with any sh (dash, busybox, macOS's bash 3.2 as sh), and use the
  options of system commands that GNU, macOS and busybox share.
- Valid in both zsh and bash: `modules/shell/`, each `interactive.sh`, the theme. Watch out:
  arrays start at 1 in zsh, at 0 in bash.
- zsh only (`*.zsh`), bash only (`*.bash`).

Defaults live in `defaults.sh` only: code reads `$om818_x`, never `${om818_x:-…}` (the lint
checks it). Globals of the POSIX sh code (bin/, lib/, install.sh, modules/env/) start with
`OM818_` for paths and variables read from the environment, else `_OM818_`; an integration's own
start with `_om818_<name>_`.

## Adding an integration

1. `integrations/<name>/integration.sh`; start from `direnv`'s, the smallest.
2. `integrations/<name>/interactive.sh` if it does something in interactive shells.
3. Its setting `om818_<name>` in the Integrations section of `defaults.sh`: `auto` when it only
   adds things, `off` when it changes a known behavior.
4. A row in [docs/integrations.md](docs/integrations.md) (the lint checks it), and tests with
   `fake_tool` (`tests/test-env.sh`, `tests/test-shells.sh`).

To try it, install your commit (committed changes only) in a throwaway home, then open a shell
there. `env -i` keeps your own `XDG_*` variables out. On macOS, add `/opt/homebrew/bin` to PATH
for a bash 4.4+:

```sh
h="$(mktemp -d)"
env -i HOME="$h" PATH=/usr/bin:/bin OM818_REPO="$PWD" OM818_REF="$(git rev-parse HEAD)" \
  sh install.sh
(cd "$h" && env -i HOME="$h" PATH=/usr/bin:/bin TERM="$TERM" LANG="$LANG" zsh -l) # or bash -l
rm -rf -- "$h"
```

`bin/om818` run from the repository would change your own install's files.

## Tests

Each test gets a fresh HOME and a fixture repository tagged `v0.1.0`. Shared code is tested in
both shells (`shell_i zsh|bash`). A useful test fails when the code it covers breaks: check a new
one by breaking that code once.

## Releases

1. Rename `## Unreleased` in `CHANGELOG.md` to `## vX.Y.Z` (`om818 update` prints these
   sections: keep that heading format), and commit it to `main`.
2. Tag a green `main`: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. Try the real install line once on a clean machine: the tests only use local copies.
4. Add a new `## Unreleased` section for the next changes.

New terminals see a new release within a day. Only `vX.Y.Z` tags are releases; don't move or
delete a pushed one: a machine on a deleted tag gets no more notices or automatic updates. Fix a
bad release with a higher tag. `install.sh` runs from main for every release: change `--temp`'s
layout only in ways every release still reads (`OM818_REF` can pick an older one).
