#!/usr/bin/env bash
source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pabloalgo
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/diegosouzapw/OmniRoute

APP="OmniRoute"
var_tags="${var_tags:-ai;proxy}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_nesting="${var_nesting:-0}"
var_keyctl="${var_keyctl:-0}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function wait_for_omniroute() {
  local timeout="${1:-90}"
  local i status
  for ((i = 0; i < timeout; i++)); do
    status="$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/login || true)"
    [[ "$status" == "200" ]] && return 0
    sleep 1
  done
  return 1
}

function rollback_update() {
  local current_version="$1"

  msg_warn "Update failed, rolling back to ${current_version}"
  systemctl stop omniroute 2>/dev/null || true
  if ! ($STD npm install -g "omniroute@${current_version}"); then
    msg_error "Package rollback failed; data backup retained at ${BACKUP_DIR}"
    exit 1
  fi

  restore_backup
  cat <<EOF >"$HOME/.omniroute"
${current_version}
EOF

  if ! systemctl start omniroute || ! wait_for_omniroute 90; then
    msg_error "Rollback restored the package and data, but the service is unhealthy"
    exit 1
  fi

  msg_ok "Rolled back to ${current_version}"
  msg_error "Update failed; rollback completed"
  exit 1
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/omniroute || ! -f /opt/omniroute/.env || ! -f "$HOME/.omniroute" ]] || ! command -v omniroute >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "omniroute" "diegosouzapw/OmniRoute"; then
    current_version="$(<"$HOME/.omniroute")"
    new_version="${CHECK_UPDATE_RELEASE#v}"

    msg_info "Stopping Service"
    systemctl stop omniroute
    msg_ok "Stopped Service"

    BACKUP_DIR="/opt/omniroute.backup"
    create_backup /opt/omniroute

    msg_info "Installing OmniRoute ${new_version}"
    if ! ($STD npm install -g "omniroute@${new_version}"); then
      rollback_update "$current_version"
    fi
    msg_ok "Installed OmniRoute ${new_version}"

    cat <<EOF >"$HOME/.omniroute"
${new_version}
EOF

    msg_info "Starting Service"
    if ! systemctl start omniroute || ! wait_for_omniroute 90; then
      rollback_update "$current_version"
    fi
    msg_ok "Started Service"

    rm -rf "$BACKUP_DIR"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:20128${CL}"
