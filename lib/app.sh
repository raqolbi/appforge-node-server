#!/usr/bin/env bash

app_list() {
  local ids
  ids="$(config_list_ids)"
  if [ -z "$ids" ]; then
    log_info "No apps configured yet (config/apps/*.env)."
    return 0
  fi
  printf '\nAvailable Apps\n\n'
  printf '%-14s %-8s %-7s %-22s %-12s\n' "ID" "Type" "Port" "Container" "Status"
  print_line
  local id
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    (
      config_load "$id" 2>/dev/null || exit 0
      local st="UNKNOWN"
      if docker_require >/dev/null 2>&1; then
        st="$(docker_status "$id")"
      fi
      printf '%-14s %-8s %-7s %-22s %-12s\n' "$id" "${APP_TYPE:-?}" "${APP_PORT:-?}" "appforge-$id" "$st"
    )
  done <<< "$ids"
}

app_create() {
  local app_id="${1:-}"
  if [ -z "$app_id" ]; then
    prompt_value "App ID" "" app_id
  fi
  if ! [[ "$app_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    die "Invalid APP_ID '$app_id' (use lowercase, digits, dashes)."
  fi
  if config_exists "$app_id"; then
    die "App '$app_id' already exists. Refusing to overwrite."
  fi

  local name="${2:-}" type="${3:-}" node_ver="${4:-}" port="${5:-}"
  local interactive=0
  [ -z "$name" ] && interactive=1

  if [ "$interactive" = 1 ]; then
    local def_name def_type="nextjs" def_node="22" def_port="3101"
    def_name="$(printf '%s' "$app_id" | sed 's/-/ /g')"
    prompt_value "App Name" "$def_name" name
    prompt_value "App Type (nextjs/node)" "$def_type" type
    prompt_value "Node Version" "$def_node" node_ver
    prompt_value "App Port" "$def_port" port
    local internal="3000"
    prompt_value "Internal Port" "$internal" internal
  else
    type="${type:-nextjs}"
    node_ver="${node_ver:-22}"
    port="${port:-3101}"
    internal="${6:-3000}"
  fi

  case "$type" in
    nextjs|node) ;;
    *) die "Invalid APP_TYPE '$type' (must be nextjs or node)." ;;
  esac
  if ! [[ "$node_ver" =~ ^[0-9]+$ ]]; then
    die "Invalid NODE_VERSION '$node_ver'."
  fi
  if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    die "Invalid APP_PORT '$port'."
  fi
  if ! [[ "$internal" =~ ^[0-9]+$ ]] || [ "$internal" -lt 1 ] || [ "$internal" -gt 65535 ]; then
    die "Invalid INTERNAL_PORT '$internal'."
  fi

  local other other_port
  for other in $(config_list_ids); do
    other_port="$(grep -E '^APP_PORT=' "$(config_file_of "$other")" 2>/dev/null | cut -d= -f2 | tr -d ' "' | tr -d "'" | head -n1)"
    if [ "$other_port" = "$port" ]; then
      die "Port $port is already in use by app '$other'."
    fi
  done

  mkdir -p "$CONFIG_DIR" "$APPS_DIR/$app_id"
  cat > "$(config_file_of "$app_id")" <<EOF
APP_ID=$app_id
APP_NAME=$name

APP_TYPE=$type
NODE_VERSION=$node_ver

APP_PORT=$port
INTERNAL_PORT=$internal

NODE_ENV=production
EOF

  docker_generate "$app_id"
  log_ok "App '$app_id' created. Artifact goes to apps/$app_id/, then run: ./appforge.sh deploy $app_id"
}

app_start() {
  local app_id="${1:?Usage: appforge.sh start <app-id>}"
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  config_validate "$app_id" || return 1
  docker_require || return 1
  [ -f "$(docker_compose_file "$app_id")" ] || docker_generate "$app_id" || return 1
  log_info "Starting '$app_id'..."
  docker_compose "$app_id" up -d || { log_error "App '$app_id': 'docker compose up -d' failed."; return 1; }
  local st
  st="$(docker_status "$app_id")"
  log_ok "App '$app_id' status: $st"
}

app_stop() {
  local app_id="${1:?Usage: appforge.sh stop <app-id>}"
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  docker_require || return 1
  if [ ! -f "$(docker_compose_file "$app_id")" ]; then
    log_info "No generated compose file; trying direct container stop..."
    if [ "$(docker_status "$app_id")" = "RUNNING" ]; then
      docker stop "$(docker_container_name "$app_id")" || { log_error "App '$app_id': 'docker stop' failed."; return 1; }
      log_ok "App '$app_id' stopped."
    else
      log_info "App '$app_id' is already stopped."
    fi
    return 0
  fi
  log_info "Stopping '$app_id'..."
  docker_compose "$app_id" stop || { log_error "App '$app_id': 'docker compose stop' failed."; return 1; }
  log_ok "App '$app_id' stopped."
}

app_restart() {
  local app_id="${1:?Usage: appforge.sh restart <app-id>}"
  config_validate "$app_id" || return 1
  docker_require || return 1
  if [ ! -f "$(docker_compose_file "$app_id")" ]; then
    log_info "No generated compose file; regenerating and starting instead..."
    app_start "$app_id"
    return $?
  fi
  log_info "Restarting '$app_id'..."
  docker_compose "$app_id" restart || { log_error "App '$app_id': 'docker compose restart' failed."; return 1; }
  log_ok "App '$app_id' restarted."
}

app_deploy() {
  local app_id="${1:?Usage: appforge.sh deploy <app-id>}"
  echo "[1/5] Validating config..."
  config_validate "$app_id" || return 1
  echo "[2/5] Validating artifact..."
  artifact_validate "$app_id" || return 1
  echo "[3/5] Generating Docker configuration..."
  docker_generate "$app_id" || return 1
  docker_require || return 1
  echo "[4/5] Building Docker image..."
  docker_compose "$app_id" build || { log_error "App '$app_id': Docker build failed."; return 1; }
  echo "[5/5] Starting container and health checking..."
  docker_compose "$app_id" up -d || { log_error "App '$app_id': container start failed."; return 1; }
  sleep 3
  local st http
  st="$(docker_status "$app_id")"
  http="$(health_http "$app_id" || true)"
  echo
  log_ok "Deployment successful. Container: $st, HTTP: $http"
}

app_rebuild() {
  local app_id="${1:?Usage: appforge.sh rebuild <app-id>}"
  config_validate "$app_id" || return 1
  docker_require || return 1
  [ -f "$(docker_compose_file "$app_id")" ] || docker_generate "$app_id" || return 1
  log_info "Rebuilding '$app_id' (no cache)..."
  docker_compose "$app_id" build --no-cache || { log_error "App '$app_id': rebuild failed."; return 1; }
  docker_compose "$app_id" up -d || { log_error "App '$app_id': container start failed."; return 1; }
  log_ok "App '$app_id' rebuilt."
}

app_logs_menu() {
  local app_id="${1:?Usage: appforge.sh logs <app-id>}"
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  docker_require || return 1
  local mode="${2:-}"
  if [ -z "$mode" ]; then
    echo
    echo "Logs for '$app_id':"
    echo "  1. Follow logs"
    echo "  2. Last 100 lines"
    echo "  3. Last 500 lines"
    echo "  4. Back"
    echo
    read -rp "Choice: " mode </dev/tty || return 0
  fi
  case "$mode" in
    1|follow) docker_compose "$app_id" logs -f --tail=100 ;;
    2|100) docker_compose "$app_id" logs --tail=100 ;;
    3|500) docker_compose "$app_id" logs --tail=500 ;;
    4|back) return 0 ;;
    *) log_error "Invalid choice."; return 1 ;;
  esac
}

app_shell() {
  local app_id="${1:?Usage: appforge.sh shell <app-id>}"
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  docker_require || return 1
  local st
  st="$(docker_status "$app_id")"
  if [ "$st" != "RUNNING" ]; then
    log_error "App '$app_id' container is not running (status: $st)."
    return 1
  fi
  docker_compose "$app_id" exec app sh
}

app_status() {
  local app_id="${1:?Usage: appforge.sh status <app-id>}"
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  config_load "$app_id" || return 1
  local cname="appforge-$app_id"
  local st="UNKNOWN" http="UNKNOWN" cpu="-" mem="-" uptime="-" image="appforge-$app_id:latest"
  if docker_require >/dev/null 2>&1; then
    st="$(docker_status "$app_id")"
    if [ "$st" = "RUNNING" ]; then
      local stats
      stats="$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$cname" 2>/dev/null || true)"
      cpu="$(printf '%s' "$stats" | awk '{print $1}')"
      mem="$(printf '%s' "$stats" | awk '{print $2}')"
      uptime="$(docker ps --filter "name=^${cname}$" --format '{{.Status}}' 2>/dev/null || true)"
      http="$(health_http "$app_id" || true)"
    fi
  fi
  echo
  print_header "$APP_NAME"
  echo
  echo "Docker:"
  echo "  Container       $st"
  echo "  Image           $image"
  echo
  echo "Application:"
  echo "  Port            ${APP_PORT:-?}"
  echo "  Internal Port   ${INTERNAL_PORT:-3000}"
  echo
  echo "Health:"
  echo "  Container       $([ "$st" = "RUNNING" ] && echo OK || echo FAIL)"
  echo "  HTTP            $http"
  echo
  echo "Runtime:"
  echo "  CPU             ${cpu:- -}"
  echo "  Memory          ${mem:- -}"
  echo "  Uptime          ${uptime:- -}"
}

app_config_menu() {
  local app_id="${1:?Usage: appforge.sh config <app-id>}"
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  local sub="${2:-}"
  if [ -n "$sub" ]; then
    case "$sub" in
      view) config_view_masked "$app_id"; return 0 ;;
      validate) config_validate "$app_id" && log_ok "Config '$app_id' is valid."; return $? ;;
      regenerate) docker_generate "$app_id"; return $? ;;
      edit) "${EDITOR:-vi}" "$(config_file_of "$app_id")"; return 0 ;;
      *) die "Usage: appforge.sh config $app_id [view|edit|validate|regenerate]" ;;
    esac
  fi
  while true; do
    echo
    print_header "App Config: $app_id"
    echo
    echo "  1. View Config"
    echo "  2. Edit Config"
    echo "  3. Validate Config"
    echo "  4. Regenerate Docker Files"
    echo "  5. Back"
    echo
    local c
    read -rp "Choice: " c </dev/tty || return 0
    case "$c" in
      1) config_view_masked "$app_id"; pause ;;
      2) "${EDITOR:-vi}" "$(config_file_of "$app_id")"; pause ;;
      3) config_validate "$app_id" && log_ok "Config '$app_id' is valid."; pause ;;
      4) docker_generate "$app_id"; pause ;;
      5) return 0 ;;
      *) log_error "Invalid choice." ;;
    esac
  done
}

app_remove() {
  local app_id="${1:?Usage: appforge.sh remove <app-id>}"
  shift
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  local force=0 purge=0 a
  for a in "$@"; do
    case "$a" in
      --force) force=1 ;;
      --purge|-f|--delete-artifact) purge=1 ;;
      *) log_error "Unknown remove flag '$a'. Available: --force --purge"; return 1 ;;
    esac
  done
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  echo
  log_warn "WARNING"
  echo
  echo "This will remove:"
  echo "- Docker container"
  echo "- generated configuration"
  echo
  echo "Source artifact will NOT be deleted."
  if [ "$purge" -eq 1 ]; then
    log_warn "With --purge, apps/$app_id/ (artifact) will ALSO be deleted."
  fi
  echo
  if [ "$force" -ne 1 ]; then
    confirm "Continue? [y/N]" || { log_info "Cancelled."; return 0; }
  fi
  if docker_require >/dev/null 2>&1 && [ -f "$(docker_compose_file "$app_id")" ]; then
    docker_compose "$app_id" down 2>/dev/null || docker rm -f "$(docker_container_name "$app_id")" 2>/dev/null || true
  else
    docker rm -f "$(docker_container_name "$app_id")" 2>/dev/null || true
  fi
  rm -rf "$GENERATED_DIR/$app_id"
  rm -f "$(config_file_of "$app_id")"
  if [ "$purge" -eq 1 ]; then
    rm -rf "$APPS_DIR/$app_id"
    log_warn "Artifact apps/$app_id/ also removed (--purge)."
  fi
  log_ok "App '$app_id' removed."
}
