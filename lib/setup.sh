#!/usr/bin/env bash

setup_detect_os() {
  if [ -f /etc/os-release ]; then
    local id_val=""
    while IFS='=' read -r k v; do
      if [ "$k" = "ID" ]; then
        id_val="$v"
        break
      fi
    done < /etc/os-release
    id_val="${id_val%\"}"
    id_val="${id_val#\"}"
    printf '%s' "${id_val:-unknown}"
  else
    printf 'unknown'
  fi
}

doctor_check() {
  local fail=0
  print_header "AppForge Doctor"
  print_line

  printf 'OS:              %s\n' "$(uname -srm)"
  if [ -f /etc/os-release ]; then
    printf 'Distro:          %s\n' "$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  fi
  printf 'User:            %s (uid=%s)\n' "$(id -un)" "$(id -u)"
  printf 'AppForge root:   %s\n' "$APPFORGE_ROOT"
  echo

  printf '[1/6] Docker binary ............ '
  if command -v docker >/dev/null 2>&1; then
    echo "OK ($(docker --version 2>/dev/null | head -n1))"
  else
    echo "FAIL (not installed)"
    fail=1
  fi

  printf '[2/6] Docker Compose v2 ........ '
  if docker compose version >/dev/null 2>&1; then
    echo "OK ($(docker compose version --short 2>/dev/null))"
  else
    echo "FAIL (need docker compose plugin)"
    fail=1
  fi

  printf '[3/6] Docker daemon access ..... '
  local docker_err
  if docker_err="$(docker info 2>&1 >/dev/null)"; then
    echo "OK"
  else
    if printf '%s' "$docker_err" | grep -qi "permission denied"; then
      echo "FAIL (permission denied on docker socket)"
      echo
      log_error "User '$(id -un)' cannot access Docker. Fix:"
      echo "  sudo usermod -aG docker $(id -un)"
      echo "  newgrp docker   # or log out and back in"
      echo
    else
      echo "FAIL (daemon not reachable)"
    fi
    fail=1
  fi

  printf '[4/6] curl/wget (health check) . '
  if command -v curl >/dev/null 2>&1; then
    echo "OK (curl)"
  elif command -v wget >/dev/null 2>&1; then
    echo "OK (wget)"
  else
    echo "WARN (neither curl nor wget; HTTP health will show UNKNOWN)"
  fi

  printf '[5/6] Directory writability .... '
  local unwritable=""
  local d
  for d in "$CONFIG_DIR" "$GENERATED_DIR" "$APPS_DIR"; do
    mkdir -p "$d" 2>/dev/null || { unwritable="$unwritable $d"; continue; }
    [ -w "$d" ] || unwritable="$unwritable $d"
  done
  if [ -z "$unwritable" ]; then
    echo "OK"
  else
    echo "FAIL (not writable:$unwritable)"
    echo
    log_error "Fix ownership, e.g.: sudo chown -R $(id -un):$(id -un) $APPFORGE_ROOT"
    echo
    fail=1
  fi

  printf '[6/6] SELinux (RHEL family) .... '
  if command -v getenforce >/dev/null 2>&1; then
    local se
    se="$(getenforce 2>/dev/null || echo Unknown)"
    echo "$se"
    if [ "$se" = "Enforcing" ]; then
      echo "       NOTE: builds read apps/<id>/ via the daemon; if you hit"
      echo "       permission denials on volume mounts later, check SELinux contexts."
    fi
  else
    echo "n/a"
  fi

  echo
  if [ "$fail" -eq 0 ]; then
    log_ok "Doctor: all critical checks passed."
  else
    log_error "Doctor: $fail critical check(s) failed. Fix above, then re-run: ./appforge.sh doctor"
  fi
  print_line
  return "$fail"
}

setup_wizard() {
  local os
  os="$(setup_detect_os)"
  echo
  print_header "AppForge First-Time Setup"
  print_line
  echo
  echo "Detected OS family: $os"
  echo "Running as: $(id -un) (uid=$(id -u))"
  echo
  echo "This wizard checks prerequisites step by step."
  echo "Nothing destructive will run without your confirmation."
  echo

  echo "Step 1 — Docker Engine + Compose plugin"
  echo
  if ! command -v docker >/dev/null 2>&1; then
    case "$os" in
      ubuntu|debian)
        echo "Install with:"
        echo "  sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin"
        ;;
      rhel|centos|rocky|almalinux|fedora|ol)
        echo "Install with:"
        echo "  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
        echo "  sudo systemctl enable --now docker"
        ;;
      *)
        echo "Install Docker Engine + Compose v2 from https://docs.docker.com/engine/install/"
        ;;
    esac
    echo
    log_warn "Docker not found. Install it, then re-run: ./appforge.sh setup"
    return 1
  fi
  log_ok "Docker found: $(docker --version 2>/dev/null | head -n1)"
  if ! docker compose version >/dev/null 2>&1; then
    case "$os" in
      ubuntu|debian) echo "Install with: sudo apt-get install -y docker-compose-plugin" ;;
      rhel|centos|rocky|almalinux|fedora|ol) echo "Install with: sudo dnf install -y docker-compose-plugin" ;;
      *) echo "Install the Compose v2 plugin from https://docs.docker.com/compose/install/" ;;
    esac
    log_warn "Compose v2 plugin missing. Install it, then re-run: ./appforge.sh setup"
    return 1
  fi
  log_ok "Compose v2 found."
  echo

  echo "Step 2 — Docker daemon access (docker group)"
  echo
  if docker info >/dev/null 2>&1; then
    log_ok "You can already talk to the Docker daemon."
  else
    log_warn "Permission denied on the Docker socket."
    echo
    echo "I can add you to the docker group with:"
    echo "  sudo usermod -aG docker $(id -un)"
    echo
    if confirm "Run it now? [y/N]"; then
      sudo usermod -aG docker "$(id -un)" \
        && log_ok "Added to docker group. Log out/in (or: newgrp docker), then re-run ./appforge.sh setup"
    else
      log_info "Skipped. Run it manually later, then re-run ./appforge.sh setup"
    fi
    return 1
  fi
  echo

  echo "Step 3 — Directory ownership"
  echo
  local need_fix=0 d
  for d in "$CONFIG_DIR" "$GENERATED_DIR" "$APPS_DIR"; do
    mkdir -p "$d"
    if [ ! -w "$d" ]; then
      log_warn "Not writable: $d"
      need_fix=1
    fi
  done
  if [ "$need_fix" -eq 1 ]; then
    echo "Fix with: sudo chown -R $(id -un):$(id -un) $APPFORGE_ROOT"
    if confirm "Run it now? [y/N]"; then
      sudo chown -R "$(id -un):$(id -un)" "$APPFORGE_ROOT" \
        && log_ok "Ownership fixed."
    else
      log_info "Skipped. Re-run setup after fixing manually."
      return 1
    fi
  else
    log_ok "config/, generated/, apps/ are writable."
  fi
  echo

  echo "Step 4 — Health check tools"
  echo
  if command -v curl >/dev/null 2>&1; then
    log_ok "curl available."
  elif command -v wget >/dev/null 2>&1; then
    log_ok "wget available (curl missing, fine)."
  else
    log_warn "Neither curl nor wget found — HTTP health will show UNKNOWN."
    case "$os" in
      ubuntu|debian) echo "Install with: sudo apt-get install -y curl" ;;
      rhel|centos|rocky|almalinux|fedora|ol) echo "Install with: sudo dnf install -y curl" ;;
    esac
  fi
  echo

  echo "Step 5 — Final verification"
  echo
  doctor_check
}

setup_menu() {
  while true; do
    echo
    print_header "Init Setup"
    echo
    echo "  1. Setup Wizard (first-time server setup)"
    echo "  2. Doctor (preflight checks)"
    echo "  3. Guide: Add App to live server"
    echo "  4. Back"
    echo
    local c
    read -rp "Choice: " c </dev/tty || return 0
    case "$c" in
      1) setup_wizard; pause ;;
      2) doctor_check; pause ;;
      3) guide_add_app | cat; pause ;;
      4) return 0 ;;
      *) log_error "Invalid choice." ;;
    esac
  done
}

guide_add_app() {
  local os
  os="$(setup_detect_os)"
  cat <<EOF
Adding a new app to a running server
=====================================

Server state assumed: AppForge already at e.g. /opt/appforge,
Docker works, other apps are RUNNING. Nothing below touches them.

1. Check the server is healthy (30 seconds):

   cd /opt/appforge
   ./appforge.sh doctor

   Must say: all critical checks passed.

2. Pick a free port:

   ./appforge.sh list
   # use an APP_PORT not in the table, e.g. 3104

3. Create the app (generates config + Dockerfile + compose):

   ./appforge.sh create myapp
   # prompts: name, type (nextjs/node), node version, APP_PORT, internal port

4. Copy the prebuilt artifact from your machine or CI:

   # from your laptop / CI, build FIRST, then:
   scp -r myapp-build/* deploy@$(hostname -f):/opt/appforge/apps/myapp/

   # ownership must match the AppForge user:
   sudo chown -R \$(id -un):\$(id -un) apps/myapp

   # sanity: package.json must exist
   ls apps/myapp/package.json

5. Deploy (validate -> generate -> build -> start -> health):

   ./appforge.sh deploy myapp

   Expected tail: Deployment successful. Container: RUNNING

6. Verify from the reverse-proxy VM:

   curl http://<app-vm-ip>:<APP_PORT>/
   # then point Nginx at <app-vm-ip>:<APP_PORT>

Rollback / update:

   # new version? just replace the artifact and re-deploy:
   scp -r myapp-build/* deploy@$(hostname -f):/opt/appforge/apps/myapp/
   ./appforge.sh deploy myapp

   # bad deploy? previous image is still local:
   ./appforge.sh rebuild myapp     # force clean rebuild
   ./appforge.sh logs myapp follow # inspect

Notes for $os hosts:
- Reverse proxy stays on its own VM; AppForge never touches Nginx/SSL.
- Restrict APP_PORT in the firewall to the reverse-proxy IP if possible.
EOF
}
