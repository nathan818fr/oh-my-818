# shellcheck shell=sh
# Tool integrations (POSIX sh, sourced by bin/om818 after lib/common.sh).
#
# Each integrations/<name>/integration.sh (<name>: a tool's name, lowercase, _ for spaces) may set:
#   om818_integration_tool       the command it needs (none: always applies)
# and may define:
#   om818_integration_check      returns 1 when it doesn't apply here, with the reason on stdout;
#                                runs first, for auto and on, also when the tool is missing,
#                                errexit off (in a condition): check each command
#   om818_integration_note       prints what `om818 status` should add when it is on
#   om818_integration_env        prints environment lines (env_set, env_path_prepend…: see
#                                modules/env/generate.sh); errors stop the generation
#   om818_integration_leftovers  prints the old locations it leaves (for `om818 status`), one per
#                                line: "<path><tab><what to do>"
#   om818_integration_uninstall  prints, the same way, what `om818 uninstall` leaves for the user
#                                to undo
# Its own helpers are named _om818_<name>_*. It is sourced by bin/om818, in a subshell.
#
# Its part for interactive shells, if any, is integrations/<name>/interactive.sh: one file for zsh
# and bash (code valid in both, $om818_shell names the shell), or interactive.<shell> when the code
# can't be shared. It runs at each start when the generated environment lists the integration and
# its tool is on PATH (and its setting isn't off in this shell). While the shell starts, it can use
# _om818_which <command> and _om818_cached <command> (modules/shell/integrations.sh; unset after);
# its own globals are named _om818_<name>_*, those only needed while starting unset after use.
#
# Its setting is om818_<name> (auto, on or off), with its default in defaults.sh's Integrations
# section: auto for integrations that only add things, off for those replacing a behavior. With
# om818_integrations_auto=off, auto means off (integration_auto_off).

integration_names() {
  local dir
  for dir in "${OM818_DIR}"/integrations/*/; do
    if [ ! -f "${dir}integration.sh" ]; then continue; fi
    dir="${dir%/}"
    printf '%s\n' "${dir##*/}"
  done
}

# Whether integrations set to auto stay off (om818_integrations_auto=off): only an explicit on
# turns one on, so those added by later releases stay off too
integration_auto_off() {
  [ "$(setting om818_integrations_auto)" = 'off' ]
}

# shellcheck disable=SC2034 # read by integration_eval and the callers
# Source an integration's file into this shell (call it in a subshell when looping)
integration_load() {
  om818_integration_tool=''
  unset -f om818_integration_check om818_integration_note om818_integration_env \
    om818_integration_leftovers om818_integration_uninstall 2>/dev/null || true
  # shellcheck source=/dev/null
  . "${OM818_DIR}/integrations/${1}/integration.sh"
}

# Load an integration and decide whether it is on, setting:
#   _OM818_I_MODE     its setting (auto, on, off)
#   _OM818_I_STATE    on or off
#   _OM818_I_REASON   why, in a few words (and its note, if any: om818_integration_note)
#   _OM818_I_FOUND    where its tool is, if any
#   _OM818_I_NO_TOOL  1 when it would be on but its tool isn't installed (yet)
#   _OM818_I_PROBLEM  1 when its setting needs fixing (invalid, or on without its tool)
# shellcheck disable=SC2034 # read by the callers
integration_eval() {
  local reason note
  integration_load "$1"
  _OM818_I_MODE="$(setting "om818_${1}")"
  _OM818_I_STATE='off' _OM818_I_FOUND='' _OM818_I_NO_TOOL=0 _OM818_I_PROBLEM=0
  case "$_OM818_I_MODE" in
  off)
    _OM818_I_REASON="om818_${1}=off"
    return 0
    ;;
  '')
    _OM818_I_REASON="no setting om818_${1} in defaults.sh"
    _OM818_I_PROBLEM=1
    return 0
    ;;
  auto)
    if integration_auto_off; then
      _OM818_I_REASON="om818_integrations_auto=off (om818_${1}=auto)"
      return 0
    fi
    ;;
  on) ;;
  *)
    _OM818_I_REASON="invalid setting om818_${1}=${_OM818_I_MODE} (auto, on or off)"
    _OM818_I_PROBLEM=1
    return 0
    ;;
  esac
  if command -v om818_integration_check >/dev/null 2>&1; then
    if ! reason="$(om818_integration_check)"; then
      _OM818_I_REASON="$reason"
      return 0
    fi
  fi
  if [ -n "$om818_integration_tool" ]; then
    _OM818_I_FOUND="$(command -v "$om818_integration_tool" 2>/dev/null || true)"
    if [ -z "$_OM818_I_FOUND" ]; then
      _OM818_I_NO_TOOL=1
      _OM818_I_REASON="${om818_integration_tool} not found"
      if [ "$_OM818_I_MODE" = 'on' ]; then
        _OM818_I_REASON="on, but ${_OM818_I_REASON}"
        _OM818_I_PROBLEM=1
      fi
      return 0
    fi
  fi
  _OM818_I_STATE='on'
  _OM818_I_REASON="om818_${1}=${_OM818_I_MODE}"
  if [ -n "$_OM818_I_FOUND" ]; then
    _OM818_I_REASON="${_OM818_I_REASON}, found ${_OM818_I_FOUND}"
  fi
  if command -v om818_integration_note >/dev/null 2>&1; then
    note="$(om818_integration_note)"
    if [ -n "$note" ]; then _OM818_I_REASON="${_OM818_I_REASON}; ${note}"; fi
  fi
}
