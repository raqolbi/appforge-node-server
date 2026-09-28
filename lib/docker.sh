#!/usr/bin/env bash

docker_require() {
  command -v docker >/dev/null 2>&1 || { log_error "Docker is not installed or not in PATH."; return 1; }
  docker compose version >/dev/null 2>&1 || { log_error "Docker Compose v2 is not available (need 'docker compose')."; return 1; }
  local info_err
  if ! info_err="$(docker info 2>&1 >/dev/null)"; then
    if printf '%s' "$info_err" | grep -qi "permission denied"; then
      log_error "Permission denied on Docker socket. Run: sudo usermod -aG docker $(id -un) && newgrp docker"
    else
      log_error "Docker daemon is not reachable. Is dockerd running? (systemctl status docker)"
    fi
    return 1
  fi
}

docker_container_name() {
  printf 'appforge-%s' "$1"
}

docker_compose_file() {
  printf '%s/%s/docker-compose.yml' "$GENERATED_DIR" "$1"
}

docker_compose() {
  local app_id="$1"
  shift
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  local compose
  compose="$(docker_compose_file "$app_id")"
  [ -f "$compose" ] || { log_error "App '$app_id': generated docker-compose.yml missing. Run: ./appforge.sh config $app_id (regenerate)."; return 1; }
  ( cd "$GENERATED_DIR/$app_id" && docker compose -p "$app_id" "$@" )
}

docker_generate() {
  local app_id="$1"
  config_validate "$app_id" || return 1

  (
    config_load "$app_id"
    local internal="${INTERNAL_PORT:-3000}"
    local template_dir="$APPFORGE_ROOT/templates/$APP_TYPE"
    [ -d "$template_dir" ] || { log_error "App '$app_id': unknown template for APP_TYPE='$APP_TYPE'."; exit 1; }

    local outdir="$GENERATED_DIR/$app_id"
    mkdir -p "$outdir"

    export APP_ID APP_NAME APP_TYPE NODE_VERSION APP_PORT NODE_ENV
    export INTERNAL_PORT="$internal"
    export CONTAINER_NAME="appforge-$app_id"
    export COMPOSE_PROJECT="$app_id"
    export BUILD_CONTEXT="../../apps/$app_id"
    export DOCKERFILE_PATH="$outdir/Dockerfile"
    export IMAGE_NAME="appforge-$app_id:latest"

    local extra_env_file="$outdir/app.env"
    : > "$extra_env_file"
    local cfg line key val
    cfg="$(config_file_of "$app_id")"
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|\#*|export\ *) continue ;;
      esac
      [[ "$line" == *"="* ]] || continue
      key="${line%%=*}"
      key="$(printf '%s' "$key" | tr -d ' \t')"
      [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
      case "$key" in
        APP_ID|APP_NAME|APP_TYPE|NODE_VERSION|APP_PORT|INTERNAL_PORT|NODE_ENV) continue ;;
      esac
      val="${line#*=}"
      val="${val%$'\r'}"
      printf '%s=%s\n' "$key" "$val" >> "$extra_env_file"
    done < "$cfg"

    render_template() {
      local src="$1" dest="$2"
      awk '{
        line = $0
        while (match(line, /\$\{[A-Za-z_][A-Za-z0-9_]*\}/)) {
          var = substr(line, RSTART+2, RLENGTH-3)
          val = ENVIRON[var]
          line = substr(line, 1, RSTART-1) val substr(line, RSTART+RLENGTH)
        }
        print line
      }' "$src" > "$dest"
    }

    render_template "$template_dir/Dockerfile" "$outdir/Dockerfile"
    render_template "$template_dir/docker-compose.yml" "$outdir/docker-compose.yml"

    touch "$extra_env_file"
  )
  log_ok "Generated Docker files for '$app_id' in generated/$app_id/."
}

docker_status() {
  local app_id="$1"
  local cname
  cname="$(docker_container_name "$app_id")"
  if ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
    printf 'NOT_CREATED'
    return 0
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$cname"; then
    printf 'RUNNING'
  else
    printf 'STOPPED'
  fi
}
