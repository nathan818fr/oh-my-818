# Changelog

What changes for you in each release, newest first: `om818 update` shows the sections of the
releases it installs.

## Unreleased

- `om818_prompt_git=off` turns git status off: no gitstatusd download, nothing started in shells.
  gitstatusd is also no longer downloaded, nor flagged by `om818 status`, when nothing else uses
  it: `om818_theme=off`, or starship drawing the prompt.
- As root, the whole `root@host` is bold red (it was a red name and an orange host). The color
  keys are now by account: `user` and `root` each color `user@host`; `host` is gone.
- `om818_completion=off` also turns `tool_completions` off (completions nothing would load).
- `om818_integrations_auto=off` keeps every integration off unless set to `on`, also those of
  later releases.

## v0.1.0

- First release.
