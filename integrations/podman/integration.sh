# shellcheck shell=sh disable=SC2034
# podman: Docker clients (docker CLI, compose, IDEs, testcontainers) talk to podman's user socket
# (enable it with: systemctl --user enable --now podman.socket)
om818_integration_tool=podman

om818_integration_check() {
  local config="${DOCKER_CONFIG:-${HOME}/.docker}/config.json" context socket
  if [ "$(uname -s)" != 'Linux' ]; then
    printf 'Linux only\n'
    return 1
  fi
  # A real Docker is left to itself: its daemon (system, rootless or Docker Desktop's), or a
  # docker context in use
  for socket in /var/run/docker.sock "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock" \
    "${HOME}/.docker/desktop/docker.sock"; do
    if [ -S "$socket" ]; then
      printf 'a Docker daemon is running (%s): left to it\n' "$socket"
      return 1
    fi
  done
  context="$(sed -n 's/.*"currentContext"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$config" 2>/dev/null || true)"
  if [ -n "$context" ] && [ "$context" != 'default' ]; then
    printf 'docker context %s in use: left to it\n' "$context"
    return 1
  fi
}

om818_integration_note() {
  local host
  host="unix://$(_om818_podman_socket)"
  if [ -n "${DOCKER_HOST:-}" ] && [ "$DOCKER_HOST" != "$host" ]; then
    # (not its value: status is shared, and it can name a host)
    printf 'DOCKER_HOST left as you set it\n'
    return 0
  fi
  if [ -S "$(_om818_podman_socket)" ]; then return 0; fi
  if [ -d /run/systemd/system ]; then
    printf 'its socket is off: systemctl --user enable --now podman.socket\n'
  else
    printf 'its socket is off (no systemd here: podman system service --time=0 &)\n'
  fi
}

om818_integration_env() {
  env_set_default DOCKER_HOST "unix://$(_om818_podman_socket)"
}

# Its user socket; root's is the system one
_om818_podman_socket() {
  if [ "$(id -u)" -eq 0 ]; then
    printf '/run/podman/podman.sock\n'
  else
    printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
  fi
}
