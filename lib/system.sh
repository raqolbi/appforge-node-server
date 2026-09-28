#!/usr/bin/env bash

system_info() {
  print_header "System Info"
  print_line
  printf 'OS:       %s\n' "$(uname -srm)"
  if command -v lsb_release >/dev/null 2>&1; then
    printf 'Distro:   %s\n' "$(lsb_release -ds 2>/dev/null)"
  fi
  printf 'Uptime:   %s\n' "$(uptime -p 2>/dev/null || uptime)"
  if command -v free >/dev/null 2>&1; then
    free -h | sed 's/^/  /'
  fi
  if command -v df >/dev/null 2>&1; then
    df -h "$APPFORGE_ROOT" | sed 's/^/  /'
  fi
}

system_docker_status() {
  docker_require || return 1
  print_header "Docker Status"
  print_line
  docker info --format 'Server: {{.ServerVersion}} | Storage: {{.Driver}} | CPUs: {{.NCPU}} | Memory: {{.MemTotal}}' 2>/dev/null || docker info 2>&1 | head -n 20
  echo
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null | grep -E 'appforge-|NAMES' || docker ps
}

system_disk_usage() {
  docker_require || return 1
  docker system df
}

system_clean_images() {
  docker_require || return 1
  log_warn "This will remove unused Docker images (docker image prune -f)."
  confirm "Continue? [y/N]" || { log_info "Cancelled."; return 0; }
  docker image prune -f
}

system_clean_cache() {
  docker_require || return 1
  log_warn "This will remove unused build cache (docker builder prune -f)."
  confirm "Continue? [y/N]" || { log_info "Cancelled."; return 0; }
  docker builder prune -f
}

system_menu() {
  while true; do
    echo
    print_header "System"
    echo
    echo "  1. Docker Status"
    echo "  2. Docker Disk Usage"
    echo "  3. Clean Unused Images"
    echo "  4. Clean Build Cache"
    echo "  5. System Info"
    echo "  6. Back"
    echo
    local c
    read -rp "Choice: " c </dev/tty || return 0
    case "$c" in
      1) system_docker_status; pause ;;
      2) system_disk_usage; pause ;;
      3) system_clean_images; pause ;;
      4) system_clean_cache; pause ;;
      5) system_info; pause ;;
      6) return 0 ;;
      *) log_error "Invalid choice." ;;
    esac
  done
}
