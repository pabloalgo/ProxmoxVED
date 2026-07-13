#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: pabloalgo
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/diegosouzapw/OmniRoute

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

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

NODE_VERSION="22" setup_nodejs

omniroute_version="$(get_latest_github_release "diegosouzapw/OmniRoute")"
msg_info "Installing OmniRoute ${omniroute_version}"
$STD timeout 600 npm install -g "omniroute@${omniroute_version}"
command -v omniroute >/dev/null 2>&1 || {
  msg_error "OmniRoute binary was not installed"
  exit 1
}
$STD omniroute --version
msg_ok "Installed OmniRoute ${omniroute_version}"

ensure_dependencies openssl
msg_info "Configuring OmniRoute"
install -d -m 0700 /opt/omniroute
umask 077
jwt_secret="$(openssl rand -hex 48)"
api_key_secret="$(openssl rand -hex 32)"
initial_password="$(openssl rand -hex 24)"
ws_bridge_secret="$(openssl rand -hex 32)"
storage_key="$(openssl rand -hex 32)"
machine_salt="$(openssl rand -hex 32)"
cli_salt="$(openssl rand -hex 32)"
cat <<EOF >/opt/omniroute/.env
NODE_ENV=production
DATA_DIR=/opt/omniroute
PORT=20128
OMNIROUTE_SERVER_HOST=0.0.0.0
JWT_SECRET=${jwt_secret}
API_KEY_SECRET=${api_key_secret}
INITIAL_PASSWORD=${initial_password}
OMNIROUTE_WS_BRIDGE_SECRET=${ws_bridge_secret}
STORAGE_ENCRYPTION_KEY=${storage_key}
STORAGE_ENCRYPTION_KEY_VERSION=v1
MACHINE_ID_SALT=${machine_salt}
OMNIROUTE_CLI_SALT=${cli_salt}
REQUIRE_API_KEY=true
ALLOW_API_KEY_REVEAL=false
AUTH_COOKIE_SECURE=false
NO_UPDATE_NOTIFIER=1
EOF
chmod 0600 /opt/omniroute/.env
unset jwt_secret api_key_secret initial_password ws_bridge_secret
unset storage_key machine_salt cli_salt
msg_ok "Configured OmniRoute"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/omniroute.service
[Unit]
Description=OmniRoute AI Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/omniroute
EnvironmentFile=/opt/omniroute/.env
ExecStart=/usr/bin/omniroute serve --no-open --no-tray --no-recovery --log
Restart=on-failure
RestartSec=5
TimeoutStopSec=60
UMask=0077
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now omniroute
if ! wait_for_omniroute 60; then
  msg_warn "First startup did not become ready; restarting once"
  systemctl restart omniroute
  if ! wait_for_omniroute 90; then
    journalctl -u omniroute.service -n 80 --no-pager >&2
    msg_error "OmniRoute did not become ready on port 20128"
    exit 1
  fi
fi
if [[ "$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://127.0.0.1:20128/v1/models || true)" != "401" ]]; then
  msg_error "OmniRoute API authentication is not enforced"
  exit 1
fi
msg_ok "Created Service"

cat <<EOF >"$HOME/.omniroute"
${omniroute_version}
EOF

motd_ssh
customize
cleanup_lxc
