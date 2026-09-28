#!/usr/bin/env bash

CONFIG_DIR="$APPFORGE_ROOT/config/apps"
DEFAULTS_FILE="$APPFORGE_ROOT/config/defaults.env"
GENERATED_DIR="$APPFORGE_ROOT/generated"
APPS_DIR="$APPFORGE_ROOT/apps"

REQUIRED_VARS="APP_ID APP_NAME APP_TYPE NODE_VERSION APP_PORT NODE_ENV"

config_list_ids() {
  if [ ! -d "$CONFIG_DIR" ]; then
    return 0
  fi
  local f base
  for f in "$CONFIG_DIR"/*.env; do
    [ -e "$f" ] || continue
    base="$(basename "$f" .env)"
    [[ "$base" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
    printf '%s\n' "$base"
  done | sort
}

config_file_of() {
  printf '%s/%s.env' "$CONFIG_DIR" "$1"
}

app_id_valid() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

config_exists() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 1
  [ -f "$(config_file_of "$1")" ]
}

config_load() {
  local app_id="$1"
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id'."; return 1; }
  local cfg
  cfg="$(config_file_of "$app_id")"
  if [ ! -f "$cfg" ]; then
    log_error "App '$app_id' is not configured."
    return 1
  fi
  unset APP_ID APP_NAME APP_TYPE NODE_VERSION APP_PORT INTERNAL_PORT NODE_ENV
  env_parse_file "$DEFAULTS_FILE" || return 1
  env_parse_file "$cfg" || return 1
}

env_parse_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*|export\ *) continue ;;
    esac
    [[ "$line" == *"="* ]] || continue
    key="${line%%=*}"
    key="$(printf '%s' "$key" | tr -d ' \t')"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    val="${line#*=}"
    val="${val%$'\r'}"
    val="$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "${#val}" -ge 2 ]; then
      case "$val" in
        \"*\"|\'*\') val="${val:1:${#val}-2}" ;;
      esac
    fi
    printf -v "$key" '%s' "$val"
    export "$key"
  done < "$file"
}

env_get_var() {
  local file="$1" want="$2"
  [ -f "$file" ] || return 0
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*|export\ *) continue ;;
    esac
    [[ "$line" == *"="* ]] || continue
    key="${line%%=*}"
    key="$(printf '%s' "$key" | tr -d ' \t')"
    [ "$key" = "$want" ] || continue
    val="${line#*=}"
    val="${val%$'\r'}"
    val="$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [ "${#val}" -ge 2 ]; then
      case "$val" in
        \"*\"|\'*\') val="${val:1:${#val}-2}" ;;
      esac
    fi
    printf '%s' "$val"
    return 0
  done < "$file"
}

config_validate() {
  local app_id="$1"
  app_id_valid "$app_id" || { log_error "Invalid app id '$app_id' (use lowercase, digits, dashes)."; return 1; }
  local cfg
  cfg="$(config_file_of "$app_id")"
  [ -f "$cfg" ] || { log_error "App '$app_id' is not configured."; return 1; }

  (
    env_parse_file "$DEFAULTS_FILE"
    env_parse_file "$cfg"

    local v
    for v in $REQUIRED_VARS; do
      if [ -z "${!v:-}" ]; then
        log_error "App '$app_id': missing required variable $v."
        exit 1
      fi
    done

    if [ "${APP_ID:-}" != "$app_id" ]; then
      log_error "App '$app_id': APP_ID mismatch (file says '${APP_ID:-}')."
      exit 1
    fi

    if ! [[ "$APP_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      log_error "App '$app_id': invalid APP_ID (use lowercase, digits, dashes)."
      exit 1
    fi

    case "${APP_TYPE:-}" in
      nextjs|node) ;;
      *) log_error "App '$app_id': invalid APP_TYPE '${APP_TYPE:-}' (must be nextjs or node)."; exit 1 ;;
    esac

    if ! [[ "${NODE_VERSION:-}" =~ ^[0-9]+$ ]]; then
      log_error "App '$app_id': invalid NODE_VERSION '${NODE_VERSION:-}'."
      exit 1
    fi

    if ! [[ "${APP_PORT:-}" =~ ^[0-9]+$ ]] || [ "$APP_PORT" -lt 1 ] || [ "$APP_PORT" -gt 65535 ]; then
      log_error "App '$app_id': invalid APP_PORT '${APP_PORT:-}'."
      exit 1
    fi

    local internal="${INTERNAL_PORT:-3000}"
    if ! [[ "$internal" =~ ^[0-9]+$ ]] || [ "$internal" -lt 1 ] || [ "$internal" -gt 65535 ]; then
      log_error "App '$app_id': invalid INTERNAL_PORT '$internal'."
      exit 1
    fi

    local other other_port
    for other in $(config_list_ids); do
      [ "$other" = "$app_id" ] && continue
      other_port="$(grep -E '^APP_PORT=' "$(config_file_of "$other")" 2>/dev/null | cut -d= -f2 | tr -d ' "' | tr -d "'" | head -n1)"
      if [ "$other_port" = "$APP_PORT" ]; then
        log_error "Port $APP_PORT is already in use by app '$other'."
        exit 1
      fi
    done
  )
}

config_view_masked() {
  local app_id="$1"
  local cfg
  cfg="$(config_file_of "$app_id")"
  config_exists "$app_id" || { log_error "App '$app_id' is not configured."; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) printf '%s\n' "$line"; continue ;;
    esac
    local key="${line%%=*}"
    local val="${line#*=}"
    if [[ "$key" =~ (PASSWORD|SECRET|KEY|TOKEN) ]]; then
      printf '%s=********\n' "$key"
    else
      printf '%s=%s\n' "$key" "$val"
    fi
  done < "$cfg"
}

artifact_validate() {
  local app_id="$1"
  local dir="$APPS_DIR/$app_id"
  if [ ! -d "$dir" ]; then
    log_error "App '$app_id': artifact directory missing: apps/$app_id/ (copy prebuilt artifact there first)."
    return 1
  fi
  if [ ! -f "$dir/package.json" ]; then
    log_error "App '$app_id': artifact invalid, package.json not found in apps/$app_id/."
    return 1
  fi
  config_load "$app_id" >/dev/null 2>&1 || return 1
  if [ "${APP_TYPE:-}" = "nextjs" ] && [ ! -d "$dir/.next" ]; then
    log_error "App '$app_id': artifact invalid, .next/ not found in apps/$app_id/ (build Next.js first: npm run build)."
    return 1
  fi
  return 0
}
