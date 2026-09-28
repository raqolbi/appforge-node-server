#!/usr/bin/env bash
set -euo pipefail

APPFORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
log_ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

die() { log_error "$*"; exit 1; }

print_header() {
  printf "${BOLD}%s${NC}\n" "$*"
}

print_line() {
  printf -- '---------------------------------------------------------\n'
}

pause() {
  read -rp "Press Enter to continue..." _ </dev/tty || true
}

confirm() {
  local prompt="${1:-Continue? [y/N]} "
  local ans
  read -rp "$prompt" ans </dev/tty || ans=""
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

prompt_value() {
  local label="$1" default_value="${2:-}" outvar="$3" input
  if [ -n "$default_value" ]; then
    read -rp "$label [$default_value]: " input </dev/tty || input=""
    input="${input:-$default_value}"
  else
    read -rp "$label: " input </dev/tty || input=""
  fi
  printf -v "$outvar" '%s' "$input"
}

menu_select_app() {
  local prompt_msg="${1:-Select app}"
  local ids
  ids="$(config_list_ids)"
  if [ -z "$ids" ]; then
    log_error "No apps configured yet (config/apps/*.env)."
    return 1
  fi
  echo "$prompt_msg:"
  local i=1 id
  local -a arr=()
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    echo "  $i. $id"
    arr+=("$id")
    i=$((i + 1))
  done <<< "$ids"
  local choice
  read -rp "Choice: " choice </dev/tty || return 1
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
    log_error "Invalid choice."
    return 1
  fi
  SELECTED_APP="${arr[$((choice - 1))]}"
  return 0
}
