# shellcheck shell=sh disable=SC2034
# 1Password CLI shell plugins: `op plugin init <tool>` authenticates CLIs (gh, aws…) with 1Password
# (https://developer.1password.com/docs/cli/shell-plugins/)
om818_integration_tool=op

om818_integration_check() {
  # (without op, the tool lookup's reason says so)
  if ! command -v op >/dev/null 2>&1; then return 0; fi
  if [ ! -f "${XDG_CONFIG_HOME:-${HOME}/.config}/op/plugins.sh" ]; then
    printf 'no shell plugin set up (op plugin init)\n'
    return 1
  fi
}
