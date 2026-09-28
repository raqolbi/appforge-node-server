#!/usr/bin/env bash
set -euo pipefail

APPFORGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/ui.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/config.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/docker.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/health.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/system.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/app.sh"
# shellcheck disable=SC1091
source "$APPFORGE_ROOT/lib/setup.sh"

usage() {
  cat <<'EOF'
Usage: ./appforge.sh <command> [args]

Commands:
  list                        List apps
  create [app-id]             Create app (interactive if no args)
  start <app-id>              Start app
  stop <app-id>               Stop app
  restart <app-id>            Restart app
  deploy <app-id>             Deploy prebuilt artifact in apps/<app-id>/
  rebuild <app-id>            Rebuild image (no cache) and start
  logs <app-id> [follow|100|500]   Show logs
  shell <app-id>              Shell into container
  status <app-id>             Status / health
  config <app-id> [view|edit|validate|regenerate]  App config
  remove <app-id> [--force] [--purge]  Remove app
  system                      System menu
  setup [wizard]              Init Setup submenu (wizard, doctor, guides)
  doctor                      Preflight checks (Docker, daemon, writability)
  guide [add-app]             Operational guides (adding app to live server)
  help                        Show this help

Run without arguments for interactive menu.
EOF
}

main_menu() {
  while true; do
    echo
    echo "╔════════════════════════════════════════════╗"
    echo "║              AppForge Launcher             ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║                                            ║"
    echo "║  1. List Apps                              ║"
    echo "║  2. Create App                             ║"
    echo "║  3. Start App                              ║"
    echo "║  4. Stop App                               ║"
    echo "║  5. Restart App                            ║"
    echo "║  6. Deploy / Update                        ║"
    echo "║  7. Rebuild                                ║"
    echo "║  8. Logs                                   ║"
    echo "║  9. Shell                                  ║"
    echo "║ 10. Status / Health                        ║"
    echo "║ 11. App Config                             ║"
    echo "║ 12. Remove App                             ║"
    echo "║                                            ║"
    echo "║ 13. System                                 ║"
    echo "║ 14. Init Setup                            ║"
    echo "║                                            ║"
    echo "║  0. Exit                                   ║"
    echo "║                                            ║"
    echo "╚════════════════════════════════════════════╝"
    echo
    local choice
    read -rp "Choice: " choice </dev/tty || exit 0
    case "$choice" in
      1) app_list; pause ;;
      2) app_create; pause ;;
      3) menu_select_app "Start which app?" && app_start "$SELECTED_APP"; pause ;;
      4) menu_select_app "Stop which app?" && app_stop "$SELECTED_APP"; pause ;;
      5) menu_select_app "Restart which app?" && app_restart "$SELECTED_APP"; pause ;;
      6) menu_select_app "Deploy which app?" && app_deploy "$SELECTED_APP"; pause ;;
      7) menu_select_app "Rebuild which app?" && app_rebuild "$SELECTED_APP"; pause ;;
      8) menu_select_app "Logs for which app?" && app_logs_menu "$SELECTED_APP"; pause ;;
      9) menu_select_app "Shell into which app?" && app_shell "$SELECTED_APP"; pause ;;
      10) menu_select_app "Status for which app?" && app_status "$SELECTED_APP"; pause ;;
      11) menu_select_app "Config for which app?" && app_config_menu "$SELECTED_APP"; pause ;;
      12) menu_select_app "Remove which app?" && app_remove "$SELECTED_APP"; pause ;;
      13) system_menu ;;
      14) setup_menu ;;
      0) echo "Bye."; exit 0 ;;
      *) log_error "Invalid choice." ;;
    esac
  done
}

cmd="${1:-menu}"
case "$cmd" in
  menu) main_menu ;;
  list) app_list ;;
  create) shift; app_create "$@" ;;
  start) app_start "${2:?Usage: appforge.sh start <app-id>}" ;;
  stop) app_stop "${2:?Usage: appforge.sh stop <app-id>}" ;;
  restart) app_restart "${2:?Usage: appforge.sh restart <app-id>}" ;;
  deploy) app_deploy "${2:?Usage: appforge.sh deploy <app-id>}" ;;
  rebuild) app_rebuild "${2:?Usage: appforge.sh rebuild <app-id>}" ;;
  logs) app_logs_menu "${2:?Usage: appforge.sh logs <app-id>}" "${3:-}" ;;
  shell) app_shell "${2:?Usage: appforge.sh shell <app-id>}" ;;
  status) app_status "${2:?Usage: appforge.sh status <app-id>}" ;;
  config) app_config_menu "${2:?Usage: appforge.sh config <app-id>}" "${3:-}" ;;
  remove) shift; app_remove "$@" ;;
  system) system_menu ;;
  setup)
    case "${2:-menu}" in
      menu) setup_menu ;;
      wizard) setup_wizard ;;
      *) log_error "Unknown setup page '${2}'. Available: wizard"; exit 1 ;;
    esac
    ;;
  doctor) doctor_check ;;
  guide)
    case "${2:-menu}" in
      menu)
        echo
        print_header "Guides"
        echo
        echo "  1. Add App to live server"
        echo "  2. Back"
        echo
        read -rp "Choice: " _gc </dev/tty || exit 0
        case "$_gc" in
          1) guide_add_app ;;
          2) exit 0 ;;
          *) log_error "Invalid choice."; exit 1 ;;
        esac
        ;;
      add-app) guide_add_app ;;
      *) log_error "Unknown guide '${2}'. Available: add-app"; exit 1 ;;
    esac
    ;;
  help|-h|--help) usage ;;
  *) log_error "Unknown command '$cmd'."; usage; exit 1 ;;
esac
