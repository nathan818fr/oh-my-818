# shellcheck shell=sh
# `om818 status` (POSIX sh, sourced by bin/om818): what oh-my-818 uses, and what can break it.
# Plain text, made to be shared when asking for help (after reading it): no environment dump, few
# values from the config, no names of env.d/ and shell.d/ files, the home directory as ~ (bin/
# om818). Rows that need action start with "!" (bin/om818 counts them).

# The installed version (computed once: git runs for it)
_OM818_VERSION=''
# 1 when the config has an error: the report shows the defaults
_OM818_STATUS_CONFIG_ERROR=''

status_report() {
  _OM818_VERSION="$(version)"
  find_zdotdir
  status_header
  # (a temporary install touches no startup file, leaves nothing behind)
  if [ -z "${OM818_TEMP:-}" ]; then
    printf '\nstartup files\n'
    status_startup_files
  fi
  printf '\nintegrations%s\n' \
    "${_OM818_STATUS_CONFIG_ERROR:+ (config.sh has an error: the defaults)}"
  status_integrations
  if [ -z "${OM818_TEMP:-}" ]; then status_leftovers; fi
}

status_header() {
  local os shells='' v names shell
  printf 'oh-my-818 %s (%s)\n' "$_OM818_VERSION" "$OM818_DIR"
  if [ "$(uname -s)" = 'Darwin' ]; then
    os="macOS $(sw_vers -productVersion 2>/dev/null || true)"
  elif [ -r /etc/os-release ]; then
    os="$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')"
  else
    os="$(uname -s)"
  fi
  if grep -qsi microsoft /proc/version; then os="${os} (WSL)"; fi
  row system "${os}, $(uname -s) $(uname -r), $(uname -m)"
  if command -v zsh >/dev/null 2>&1; then
    v="$(zsh -fc 'print -r -- $ZSH_VERSION' 2>/dev/null || true)"
    case "$v" in
    [0-4].* | 5.0.*) v="${v} (too old: oh-my-818 needs 5.1+)" ;;
    esac
    shells="zsh ${v}"
  fi
  if command -v bash >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    v="$(bash -c 'printf %s "${BASH_VERSION%%(*}"' 2>/dev/null || true)"
    case "$v" in
    [0-3].* | 4.[0-3]*) v="${v} (too old: only the environment; oh-my-818 needs 4.4+)" ;;
    esac
    shells="${shells:+${shells}, }bash ${v}"
  fi
  # (in a temporary bash, SHELL is the install's wrapper)
  case "${SHELL:-unknown}" in
  "${OM818_TEMP:-/nowhere}"/*) row shells "${shells}, login shell: the temporary install's" ;;
  *) row shells "${shells}, login shell ${SHELL:-unknown}" ;;
  esac
  # A login shell that isn't one of them (e.g. /bin/sh, useradd's default): no oh-my-818 in
  # terminals and SSH sessions. No SHELL (docker exec, cron): dash and busybox, unlike bash, don't
  # set it
  shell="${SHELL:-}"
  case "${shell##*/}" in
  zsh | bash | '') ;;
  *)
    shell="$(command -v zsh || command -v bash)"
    # shellcheck disable=SC2016 # $USER as is: the report may be shared
    row login "! ${SHELL} runs no oh-my-818: chsh -s ${shell}"' (else: sudo usermod -s … $USER)'
    ;;
  esac
  row terminal "TERM=${TERM:-}, LANG=${LANG:-}${LC_ALL:+, LC_ALL=${LC_ALL}}"
  row update "$(status_update)"
  row settings "$(status_config)"
  row 'your files' "$(status_user_files)"
  # shellcheck disable=SC2154 # set by config_load
  if [ -n "$om818_sandbox_only" ]; then
    # shellcheck disable=SC2086 # split on purpose
    names="$(printf '%s, ' $om818_sandboxes)"
    row 'sandbox only' "${om818_sandbox_only} (only inside: ${names%, })"
  fi
  row environment "$(status_env)"
  row gitstatusd "$(status_gitstatusd)"
}

status_update() {
  local file="${OM818_STATE_DIR}/update" mode latest checked skip failed now age
  mode="$(setting om818_update)"
  if [ -n "${OM818_TEMP:-}" ]; then
    printf 'temporary install, in %s: removed once its last shell exits\n' "$OM818_TEMP"
    return 0
  fi
  if [ -e "${OM818_STATE_DIR}/install-pending" ]; then
    printf '! an update stopped before its end: om818 update finishes it\n'
    return 0
  fi
  if ! updatable; then
    printf 'read-only install: updated where it comes from\n'
    return 0
  fi
  if ! on_release >/dev/null; then
    printf 'a development version: no notices (om818 update installs the latest release)\n'
    return 0
  fi
  if [ "$mode" = 'off' ]; then
    printf 'no automatic check (om818_update=off): om818 update checks now\n'
    return 0
  fi
  checked="$(sed -n 's/^checked=//p' "$file" 2>/dev/null || true)"
  # (digits only: the value goes into arithmetic, where bash as sh would run a $(…) in it)
  case "$checked" in *[!0-9]*) checked='' ;; esac
  if [ -z "$checked" ]; then
    printf 'not checked yet (om818_update=%s: new terminals check once a day)\n' "$mode"
    return 0
  fi
  now="$(date +%s)"
  age="$(((now - checked) / 3600))"
  if [ "$age" -lt 1 ]; then
    age='less than 1 h ago'
  elif [ "$age" -lt 48 ]; then
    age="${age} h ago"
  else
    age="$((age / 24)) days ago"
  fi
  latest="$(sed -n 's/^latest=//p' "$file")"
  skip="$(sed -n 's/^skip=//p' "$file")"
  failed="$(sed -n 's/^failed=//p' "$file")"
  if [ -n "$latest" ] && [ "$latest" != "$_OM818_VERSION" ]; then
    printf '%s available: om818 update (checked %s)\n' "$latest" "$age"
  elif [ -n "$skip" ] && [ "$skip" = "$(latest_tag)" ] && [ "$skip" != "$_OM818_VERSION" ]; then
    printf '%s skipped after a rollback: om818 update installs it\n' "$skip"
  elif [ -n "$failed" ]; then
    printf 'the last check failed (offline?), %s; om818_update=%s\n' "$age" "$mode"
  else
    printf 'up to date (checked %s; om818_update=%s)\n' "$age" "$mode"
  fi
}

# The config: readable, only known settings, valid on/off/auto values
status_config() {
  local err problems shell=bash
  if [ ! -e "$OM818_CONFIG" ]; then
    printf 'none (defaults): %s\n' "$OM818_CONFIG"
    return 0
  fi
  # Its line number (zsh: "config.sh:3:", bash: "config.sh: line 3:"), not the shell's message:
  # that can quote the line (a secret). In zsh, a typo in a table's name is such an error: so the
  # unknown names are shown too
  if ! err="$(config_dump 2>&1 >/dev/null)"; then
    err="$(printf '%s\n' "$err" |
      sed -n 's/.*config\.sh:\( line\)\{0,1\} *\([0-9][0-9]*\):.*/\2/p' | head -n 1)"
    problems="$(config_problems)"
    if command -v zsh >/dev/null 2>&1; then shell=zsh; fi
    # (after defaults.sh, as the shells read it: its tables are declared there)
    printf "! %s: an error%s%s: %s -c '. %s; . %s' shows it\n" "$OM818_CONFIG" \
      "${err:+ at line ${err}}" "${problems:+ (${problems})}" "$shell" \
      "${OM818_DIR}/defaults.sh" "$OM818_CONFIG"
    return 0
  fi
  problems="$(config_problems)"
  if [ -z "$problems" ]; then
    printf '%s: ok\n' "$OM818_CONFIG"
  else
    printf '! %s: %s; all settings: %s\n' "$OM818_CONFIG" "$problems" "${OM818_DIR}/defaults.sh"
  fi
}

# How many files env.d/ and shell.d/ hold that the shells load (not their names: they may be
# private), and env.d's with a syntax error: sh stops reading ~/.profile at it (e.g. dash, which
# reads it at login on Debian)
status_user_files() {
  local dir file n out='' broken=0
  # (env.d/ loads only *.sh)
  for dir in "$OM818_ENV_D" "$OM818_SHELL_D"; do
    n=0
    for file in "$dir"/*.sh "$dir"/*.zsh "$dir"/*.bash; do
      case "${dir}:${file}" in "${OM818_ENV_D}:"*.zsh | "${OM818_ENV_D}:"*.bash) continue ;; esac
      if [ -f "$file" ]; then n=$((n + 1)); fi
    done
    out="${out:+${out}, }${dir##*/}: ${n}"
  done
  for file in "$OM818_ENV_D"/*.sh; do
    if [ -f "$file" ] && ! sh -n "$file" 2>/dev/null; then broken=$((broken + 1)); fi
  done
  if [ "$broken" -gt 0 ]; then printf '! '; fi
  printf '%s (%s)' "$out" "$OM818_CONFIG_DIR"
  if [ "$broken" -gt 0 ]; then
    printf '; %s env.d file(s) with a syntax error: sh -n %s/*.sh' "$broken" "$OM818_ENV_D"
  fi
  printf '\n'
}

# The environment file: its state, and whether it matches what would be generated now (a tool
# installed or removed since, a Docker daemon started…)
status_env() {
  local now current
  if [ ! -r "$OM818_ENV" ]; then
    printf '! not generated: om818 env\n'
    return 0
  elif [ ! -w "$OM818_STATE_DIR" ]; then
    printf '! %s: read-only (a mount, another owner?): nothing there can be updated\n' \
      "$OM818_STATE_DIR"
    return 0
  elif [ -n "$_OM818_STATUS_CONFIG_ERROR" ]; then
    printf '! %s: config.sh has an error: fix it, then open a new terminal\n' "$OM818_ENV"
    return 0
  elif [ -e "$OM818_CONFIG" ] && [ "$OM818_CONFIG" -nt "$OM818_ENV" ]; then
    printf '%s: older than config.sh, regenerated by the next new terminal (or om818 env)\n' \
      "$OM818_ENV"
    return 0
  elif [ ! -e "$OM818_CONFIG" ] && [ "$OM818_CONFIG_DIR" -nt "$OM818_ENV" ]; then
    printf '%s: config.sh removed since, regenerated by the next new terminal (or om818 env)\n' \
      "$OM818_ENV"
    return 0
  elif ! head -n 1 "$OM818_ENV" | grep -qF "om818 ${_OM818_VERSION}:"; then
    printf '%s: from another version, regenerated by the next new terminal (or om818 env)\n' \
      "$OM818_ENV"
    return 0
  fi
  now="$(env_render 2>/dev/null)" || now=''
  current="$(cat -- "$OM818_ENV")"
  if [ -n "$now" ] && [ "$now" != "$current" ]; then
    printf '! %s: out of date (tools changed since): om818 env\n' "$OM818_ENV"
  else
    printf '%s: ok\n' "$OM818_ENV"
  fi
}

status_gitstatusd() {
  local cache="${OM818_CACHE_DIR}/gitstatus" daemon
  if daemon="$(GITSTATUS_CACHE_DIR="$cache" sh "${OM818_DIR}/vendor/gitstatus/install" -n \
    -- printf '%s\n' 2>/dev/null)"; then
    printf '%s\n' "${daemon%%"
"*}"
  elif [ -n "${OM818_TEMP:-}" ]; then
    printf 'not downloaded in a temporary install (no git status in the prompt)\n'
  elif [ -e "$cache" ] && [ ! -w "$cache" ]; then
    printf '! not downloaded, and its folder is read-only: run om818 install where it comes from\n'
  else
    printf '! not downloaded (no git status in the prompt): om818 install\n'
  fi
}

status_startup_files() {
  local zdir login state file
  if command -v zsh >/dev/null 2>&1; then
    zdir="$(zdotdir)"
    file_row "${HOME}/.zshenv" "$(startup_state "${HOME}/.zshenv" 'om818/env.sh')" \
      'loads the environment in zsh'
    if [ -z "$_OM818_ZSH_ZDOTDIR" ]; then
      path_row "${HOME}/.zshenv" "! doesn't set ZDOTDIR: zsh reads ~/.zshrc, not ${zdir}/.zshrc" \
        '(om818 install adds the line)'
    fi
    state=missing
    if shell_loads_om818 zsh; then state=ok; fi
    file_row "${zdir}/.zshrc" "$state" 'loads oh-my-818 in zsh'
  fi
  file_row "${HOME}/.profile" "$(startup_state "${HOME}/.profile" 'om818/env.sh')" \
    'loads the environment in sh and login shells'
  login="$(bash_login_file)"
  if [ -n "$login" ]; then
    state="$(startup_state "$login" 'om818/env.sh')"
    if [ "$state" = 'missing' ]; then
      state='! no om818 line: bash login shells read it instead of ~/.profile: om818 install'
      state="${state} adds it"
    fi
    file_row "$login" "$state" 'loads the environment in bash login shells'
  fi
  if [ -e "${HOME}/.bashrc" ]; then
    state=missing
    if shell_loads_om818 bash; then state=ok; fi
    file_row "${HOME}/.bashrc" "$state" 'loads the environment and oh-my-818 in bash'
  elif bash_supported; then
    path_row "${HOME}/.bashrc" '! absent: bash starts without oh-my-818 (om818 install adds it)'
  fi
  if [ -n "${zdir:-}" ] && [ "$zdir" != "$HOME" ]; then
    for file in .zshrc .zprofile .zlogin .zlogout; do
      if [ ! -e "${HOME}/${file}" ]; then continue; fi
      if [ ! -s "${HOME}/${file}" ] && [ ! -w "${HOME}/${file}" ]; then
        path_row "${HOME}/${file}" "empty read-only guard: ok (zsh reads ${zdir})"
      elif [ -s "${HOME}/${file}" ] && ! cmp -s -- "${HOME}/${file}" "/etc/skel/${file}"; then
        # (written again since it was set aside, e.g. by a tool's installer: a second mv would
        # overwrite the copy uninstall puts back)
        if [ -e "${HOME}/${file}.pre-om818" ]; then
          path_row "${HOME}/${file}" "! not read (zsh reads ${zdir}/${file}), written since" \
            "$(tilde "${HOME}/${file}.pre-om818") was set aside: copy its new lines" \
            "(tool blocks to ${zdir}/${file}), then remove it (keep the copy): rm ~/${file}"
        else
          path_row "${HOME}/${file}" "! not read (zsh reads ${zdir}/${file}): copy your lines" \
            "(aliases to shell.d/, exports to env.d/, tool blocks to ${zdir}/${file}), then set" \
            "it aside: mv ~/${file} ~/${file}.pre-om818 (om818 uninstall puts it back)"
        fi
      fi
    done
  fi
  if [ "$(setting om818_protect_startup_files)" = 'on' ]; then
    while IFS= read -r file; do
      if [ -e "$file" ] && [ -w "$file" ]; then
        path_row "$file" '! writable, while om818_protect_startup_files=on:' \
          'om818 install protects it'
      fi
    done <<EOF
$(startup_files)
$(startup_guards)
EOF
  fi
  for file in oh-my-zsh.sh prezto zinit antidote zplug; do
    if [ -n "${zdir:-}" ] && grep -qs "$file" "${zdir}/.zshrc"; then
      path_row "${zdir}/.zshrc" "! also loads ${file}: two setups conflict: remove its lines" \
        '(docs/coming-from.md)'
    fi
  done
}

status_integrations() {
  local name file line shell
  for name in $(integration_names); do
    (
      integration_eval "$name"
      if [ "$_OM818_I_PROBLEM" -eq 1 ]; then printf '!'; else printf ' '; fi
      printf ' %-17s %-4s %s\n' "$name" "$_OM818_I_STATE" "$_OM818_I_REASON"
    )
  done
  # Tools' init scripts that failed (_om818_cached), with their first line of error
  for file in "${OM818_CACHE_DIR}"/eval/*.failed; do
    if [ ! -f "$file" ]; then continue; fi
    line="$(head -n 1 -- "$file")"
    name="${file##*/}"
    # (named <shell>-<command>, its characters other than letters, digits, . and - as -)
    name="${name%.failed}"
    shell="${name%%-*}"
    name="${name#*-}"
    path_row "${name%%-*}" "! its setup command failed in ${shell}: ${line:-no output}" \
      '(retried when the tool changes)'
  done
}

# Old locations left in HOME, which oh-my-818 doesn't use or move: old history files, and those
# integrations report (e.g. a tool's folder the xdg integration leaves where it is)
status_leftovers() {
  local out='' file shell name rows
  for shell in zsh bash; do
    file="${HOME}/.${shell}_history"
    # (om818_history=off: the shells' own, in use)
    # shellcheck disable=SC2154 # set by config_load
    if [ ! -s "$file" ] || [ "$om818_history" = 'off' ]; then continue; fi
    if [ -e "$(history_file "$shell")" ]; then
      out="${out}$(path_row "$file" "old ${shell} history, no longer read (oh-my-818's:" \
        "$(tilde "$(history_file "$shell")"))")
"
    else
      out="${out}$(path_row "$file" "old ${shell} history, not used: om818 install copies it")
"
    fi
  done
  for name in $(integration_names); do
    rows="$(
      integration_eval "$name"
      if [ "$_OM818_I_STATE" = 'on' ] &&
        command -v om818_integration_leftovers >/dev/null 2>&1; then
        om818_integration_leftovers
      fi
    )"
    while IFS='	' read -r file line; do
      if [ -n "$file" ]; then out="${out}$(path_row "$file" "$line")
"; fi
    done <<EOF
$rows
EOF
  done
  if [ -n "$out" ]; then
    printf '\nold locations (optional tidying)\n%s' "$out"
  fi
}

### Helpers

# A row of the header; text starting with "! ": it needs action
# usage: row <label> <text>
row() {
  case "$2" in
  '! '*) printf '! %-12s %s\n' "$1" "${2#! }" ;;
  *) printf '  %-12s %s\n' "$1" "$2" ;;
  esac
}

# A row about a file; text starting with "! ": it needs action
# usage: path_row <path> <text>...
path_row() {
  local path="$1" text
  shift
  text="$*"
  case "$text" in
  '! '*) printf '! %s: %s\n' "$path" "${text#! }" ;;
  *) printf '  %s: %s\n' "$path" "$text" ;;
  esac
}

# A startup file's state; read-only ones say so (protected from tools that append to them)
file_row() {
  local what="$3"
  if [ -e "$1" ] && [ ! -w "$1" ]; then what="${what:+${what}, }read-only"; fi
  what="${what:+ (${what})}"
  case "$2" in
  ok) printf '  %s: ok%s\n' "$1" "$what" ;;
  absent) printf '! %s: absent%s: om818 install creates it\n' "$1" "$what" ;;
  missing)
    if [ -e "$1" ] && [ ! -w "$1" ]; then
      printf '! %s: no om818 line%s: add it yourself (om818 install shows it)\n' "$1" "$what"
    else
      printf '! %s: no om818 line%s: om818 install adds it\n' "$1" "$what"
    fi
    ;;
  *) path_row "$1" "$2" ;;
  esac
}
