# shellcheck shell=sh disable=SC2034
# mise: one manager for the versions of every language and tool (https://mise.jdx.dev)
om818_integration_tool=mise

# Its shims, for what doesn't run an interactive shell: desktop apps, IDEs, scripts. oh-my-818's
# own folder holds its developers' mise.toml: ignored, else mise asks to trust it in that folder
# (a list of your own: set it in env.d/, with this folder)
om818_integration_env() {
  env_path_prepend "${MISE_DATA_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/mise}/shims"
  env_set MISE_IGNORED_CONFIG_PATHS "$OM818_DIR"
}
