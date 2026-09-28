#!/usr/bin/env bash

health_container() {
  local app_id="$1"
  local st
  st="$(docker_status "$app_id")"
  case "$st" in
    RUNNING) printf 'OK'; return 0 ;;
    *) printf 'FAIL'; return 1 ;;
  esac
}

health_http() {
  local app_id="$1"
  config_load "$app_id" >/dev/null 2>&1 || { printf 'UNKNOWN'; return 1; }
  local port="${APP_PORT:-}"
  [ -n "$port" ] || { printf 'UNKNOWN'; return 1; }
  local url="http://127.0.0.1:${port}"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 5 -o /dev/null "$url" 2>/dev/null; then
      printf 'OK'
    else
      printf 'FAIL'; return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -T 5 -O /dev/null "$url" 2>/dev/null; then
      printf 'OK'
    else
      printf 'FAIL'; return 1
    fi
  else
    printf 'UNKNOWN'; return 1
  fi
}
