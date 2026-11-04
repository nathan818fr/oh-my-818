# shellcheck shell=bash disable=SC1090,SC1091,SC2154
# Updates (code valid in zsh and bash): once a day, `om818 check` looks for a new release in the
# background; when one exists, each new shell prints one line (om818_update=notify) or updates
# (om818_update=auto). Not for an install this shell can't update: read-only (e.g. mounted in a
# sandbox), or another user's (root keeping HOME under sudo: git would leave root's files there).
# Not in the shells `om818` starts to inspect the setup (OM818_PROBE=1).

function _om818_update() {
  local file="${_om818_state_dir}/update" line current='' latest='' checked=0
  if [[ ! -w "${OM818_DIR}/.git" || ! -O "${OM818_DIR}/.git" || -n "$_om818_probe" ]]; then
    return 0
  fi
  if [[ -r "$file" ]]; then
    while IFS= read -r line; do
      case "$line" in
      current=*) current="${line#*=}" ;;
      latest=*) latest="${line#*=}" ;;
      checked=*) checked="${line#*=}" ;;
      esac
    done <"$file"
  fi
  _om818_now
  # (a number only: it goes into arithmetic, which would run what a crafted file holds)
  if [[ -z "$checked" || "$checked" == *[!0-9]* ]]; then checked=0; fi
  if [[ "$((REPLY - checked))" -ge 86400 ]]; then
    # In / (a tool there could read the folder's config, e.g. a mise shim for git); in a
    # subshell: not a job of this shell, so no "[1] Done" notice
    (cd / && "${OM818_DIR}/bin/om818" check >/dev/null 2>&1 &)
  fi
  if [[ -z "$latest" || "$latest" == "$current" ]]; then return 0; fi
  if [[ "$om818_update" == 'auto' ]]; then
    # What the background check fetched: no network here, the shell doesn't wait
    (cd / && "${OM818_DIR}/bin/om818" update --no-fetch)
  else
    printf 'oh-my-818 %s is available (you have %s): om818 update\n' "$latest" "$current"
  fi
}
_om818_update
unset -f _om818_update
