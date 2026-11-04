# shellcheck shell=sh
# Releases (POSIX sh, sourced by bin/om818 after lib/common.sh): only releases (vX.Y.Z tags) run,
# never a branch. The state folder keeps:
#   update    when the last check ran (checked=, seconds since the epoch), what it found
#             (current=, latest=), the release a rollback left (skip=), and failed=1 when the
#             check couldn't fetch (older versions ignore the lines they don't know)
#   previous  the commit before the last update or rollback
#   install-pending  the commit being checked out, until its install is done: an update or
#             rollback cut short there (a closed terminal) is finished by the next update,
#             rollback or daily check (release_finish)
# Git never asks anything (no terminal prompt, no SSH question): it fails instead.

# Update to the latest release; with --no-fetch, to the latest one already fetched (by the
# background check: no network, for the automatic update of a starting shell)
release_update() {
  local before after
  if ! updatable; then
    error "this install is read-only ($(tilde "$OM818_DIR")): update it where it comes from" \
      '(e.g. the host it is mounted from)'
    return 1
  fi
  release_finish || return 1
  if [ "${1:-}" != '--no-fetch' ] && ! release_fetch 2>/dev/null; then
    error "cannot reach $(git -C "$OM818_DIR" remote get-url origin 2>/dev/null) (offline?):" \
      "still on $(version)"
    return 1
  fi
  after="$(latest_tag)"
  if [ -z "$after" ]; then
    info 'oh-my-818: no release published yet: nothing to update'
    return 0
  fi
  before="$(version)"
  if [ "$(git -C "$OM818_DIR" rev-parse HEAD)" = \
    "$(git -C "$OM818_DIR" rev-parse "refs/tags/${after}^{commit}")" ]; then
    release_record "$after"
    info "oh-my-818 is up to date (${after})"
    return 0
  fi
  release_unedited update || return 1
  release_checkout "refs/tags/${after}"
  release_record "$after"
  info "oh-my-818 updated: ${before} -> ${after}. New terminals use it (om818 rollback goes back)."
  release_changes "$before" "$after"
}

# Print what changed, from the new version's CHANGELOG.md: the sections from <to> down to <from>
# (excluded), or <to>'s alone when <from> has none (e.g. a development version). The "## vX.Y.Z"
# headings are read by older versions (this code, in the version being replaced): keep them so
# usage: release_changes <from> <to>
release_changes() {
  local file="${OM818_DIR}/CHANGELOG.md" from="## ${1}" line on=0
  if ! grep -qx -- "## ${2}" "$file" 2>/dev/null; then return 0; fi
  if ! grep -qx -- "$from" "$file"; then from=''; fi
  info 'What changed:'
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "## ${2}" ]; then on=1; fi
    if [ "$on" -eq 0 ]; then continue; fi
    case "$line" in
    '## '*)
      # (down to <from>'s heading, else the next one)
      if [ "$line" != "## ${2}" ] && { [ -z "$from" ] || [ "$line" = "$from" ]; }; then break; fi
      printf '  %s\n' "${line#'## '}"
      ;;
    *[![:space:]]*) printf '    %s\n' "$line" ;;
    esac
  done <"$file" >&2
}

release_rollback() {
  local before target
  if ! updatable; then
    error "this install is read-only ($(tilde "$OM818_DIR")): roll it back where it comes from"
    return 1
  fi
  release_finish || return 1
  if [ ! -s "${OM818_STATE_DIR}/previous" ]; then
    error 'no previous release to go back to'
    return 1
  fi
  target="$(cat -- "${OM818_STATE_DIR}/previous")"
  before="$(version)"
  release_unedited 'roll back' || return 1
  # Before the checkout: a rollback cut short is finished as such (release_finish). Once: a second
  # rollback would go forward again. No notice (nor auto update) for the release left, until a
  # newer one comes out
  rm -f -- "${OM818_STATE_DIR}/previous"
  release_record '' "$before"
  release_checkout "$target" rollback
  info "oh-my-818 rolled back: ${before} -> $(version). New terminals use it. ${before} won't be"
  info "announced again; om818 update installs it."
}

# Status 1, with a message, when files of the checkout were edited: git would refuse to check out
# another version
# usage: release_unedited <what can't be done>
release_unedited() {
  if [ -n "$(git -C "$OM818_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    error "files of $(tilde "$OM818_DIR") were edited, so it can't ${1}: undo them with" \
      "git -C $(tilde "$OM818_DIR") checkout -- . (your settings go in config.sh)"
    return 1
  fi
}

# Look for a new release, for the notice of new terminals (no output: run in the background)
release_check() {
  local file="${OM818_STATE_DIR}/update" latest skip=''
  if ! updatable; then return 0; fi
  skip="$(sed -n 's/^skip=//p' "$file" 2>/dev/null || true)"
  latest="$(sed -n 's/^latest=//p' "$file" 2>/dev/null || true)"
  # Recorded first (checked=now): shells starting meanwhile don't check too
  release_record "$latest" "$skip"
  if ! release_fetch; then
    release_record "$latest" "$skip" 1
    return 0
  fi
  # (read again: a rollback during the fetch records the release it left)
  skip="$(sed -n 's/^skip=//p' "$file" 2>/dev/null || true)"
  latest="$(latest_tag)"
  # Development installs (not on a release) get no notice
  if ! on_release >/dev/null || [ "$latest" = "$skip" ]; then
    latest=''
  fi
  release_record "$latest" "$skip"
}

# Local tags mirror GitHub's: a tag deleted there (e.g. pushed by mistake) goes away, a moved one
# follows (--force)
release_fetch() {
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" \
    git -C "$OM818_DIR" fetch --quiet --prune --prune-tags --tags --force origin
}

# Check out a release or commit (detached), keeping the current one as "previous" (not for a
# rollback), then set up what depends on the version (environment, gitstatusd) with the new
# version's own `om818 install`: this file's code is the old version's, already in memory. The
# bookkeeping comes first: once the checkout starts, only its install is left (release_finish)
# usage: release_checkout <release or commit> [rollback]
release_checkout() {
  local current
  current="$(git -C "$OM818_DIR" rev-parse HEAD)"
  mkdir -p -- "$OM818_STATE_DIR"
  git -C "$OM818_DIR" rev-parse "${1}^{commit}" >"${OM818_STATE_DIR}/install-pending"
  if [ "${2:-}" != rollback ]; then printf '%s\n' "$current" >"${OM818_STATE_DIR}/previous"; fi
  git -C "$OM818_DIR" -c advice.detachedHead=false checkout --quiet --detach "$1"
  "${OM818_DIR}/bin/om818" install --quiet
}

# Print the commit of an update or rollback cut short (install-pending). Status 1 when there is
# none; a file naming no commit here (a tag deleted upstream, then gc) is dropped: the install
# goes on with the version checked out
release_pending() {
  local file="${OM818_STATE_DIR}/install-pending" target
  if [ ! -e "$file" ]; then return 1; fi
  target="$(cat -- "$file" 2>/dev/null)" || target=''
  case "$target" in
  '' | *[!0-9a-f]*) ;;
  *)
    if git -C "$OM818_DIR" rev-parse --quiet --verify "${target}^{commit}" >/dev/null; then
      printf '%s\n' "$target"
      return 0
    fi
    ;;
  esac
  rm -f -- "$file"
  return 1
}

# Finish an update or rollback cut short: its checkout again, which may have stopped half-way (a
# tree mixing both versions: "edited" files), then its install
release_finish() {
  local target
  if [ ! -e "${OM818_STATE_DIR}/install-pending" ]; then return 0; fi
  # (status checked: callers test this function, which turns errexit off here)
  if target="$(release_pending)"; then
    git -C "$OM818_DIR" -c advice.detachedHead=false checkout --quiet --force --detach "$target" ||
      return 1
  fi
  "${OM818_DIR}/bin/om818" install --quiet || return 1
}

# Write the update file: now as the check time, the current version, the latest release (empty:
# nothing to announce), the release to skip, and whether the check failed
# usage: release_record <latest> [<skip> [<failed: 1>]]
release_record() {
  mkdir -p -- "$OM818_STATE_DIR"
  printf 'checked=%s\ncurrent=%s\nlatest=%s\nskip=%s\nfailed=%s\n' "$(date +%s)" "$(version)" \
    "$1" "${2:-}" "${3:-}" >"${OM818_STATE_DIR}/update"
}

# After an install or repair, which may have changed the version: the update file's current=
# follows, so new shells don't announce the release already installed
release_record_current() {
  local file="${OM818_STATE_DIR}/update" checked latest skip
  if [ ! -s "$file" ]; then return 0; fi
  checked="$(sed -n 's/^checked=//p' "$file")"
  latest="$(sed -n 's/^latest=//p' "$file")"
  skip="$(sed -n 's/^skip=//p' "$file")"
  printf 'checked=%s\ncurrent=%s\nlatest=%s\nskip=%s\n' "$checked" "$(version)" "$latest" "$skip" \
    >"$file"
}
