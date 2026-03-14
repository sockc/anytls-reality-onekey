#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
BASE_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=lib/common.sh
source "$BASE_DIR/lib/common.sh"
# shellcheck source=lib/system.sh
source "$BASE_DIR/lib/system.sh"
# shellcheck source=lib/firewall.sh
source "$BASE_DIR/lib/firewall.sh"

APP_NAME="AnyTLS + REALITY"
WORK_DIR="/etc/anytls-reality"
SERVER_CONFIG="${WORK_DIR}/server.json"
CLIENT_CONFIG="${WORK_DIR}/client-outbound.json"
INFO_FILE="${WORK_DIR}/node-info.txt"
SERVICE_NAME="sing-box"
DEFAULT_PORT="443"
DEFAULT_REALITY_DOMAIN="www.cloudflare.com"

install_or_reinstall() {
  need_root
  ensure_supported_os
  ensure_basic_tools
  ensure_singbox_installed

  mkdir -p "$WORK_DIR"

  local listen_port password reality_domain short_id key_answer key_pair private_key public_key public_ip

  listen_port="$(prompt_port "请输入监听端口" "$DEFAULT_PORT")"
  password="$(prompt_or_random "请输入 AnyTLS 密码" 24)"
  reality_domain="$(prompt_with_default "请输入 REALITY 伪装域名" "$DEFAULT_REALITY_DOMAIN")"
  short_id="$(prompt_short_id "请输入 short_id（留空自动生成）")"
  key_answer="$(prompt_with_default "是否自动生成 REALITY 密钥对？[Y/n]" "Y")"

  if [[ "$key_answer" =~ ^[Nn]$ ]]; then
    private_key="$(prompt_required "请输入 REALITY private_key")"
    public_key="$(prompt_required "请输入 REALITY public_key")"
  else
    key_pair="$(sing-box generate reality-keypair)"
    private_key="$(awk '/PrivateKey/ {print $NF}' <<< "$key_pair")"
    public_key="$(awk '/PublicKey/ {print $NF}' <<< "$key_pair")"
    if [[ -z "$private_key" || -z "$public_key" ]]; then
      die "REALITY 密钥对生成失败，请检查 sing-box 是否安装正常。"
    fi
  fi

  cat > "$SERVER_CONFIG" <<JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${listen_port},
      "users": [
        {
          "name": "self",
          "password": "${password}"
        }
      ],
      "tls": {
        "enabled": true,
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${reality_domain}",
            "server_port": 443
          },
          "private_key": "${private_key}",
          "short_id": [
            "${short_id}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON

  cat > "$CLIENT_CONFIG" <<JSON
{
  "outbounds": [
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "YOUR_SERVER_IP_OR_DOMAIN",
      "server_port": ${listen_port},
      "password": "${password}",
      "tls": {
        "enabled": true,
        "server_name": "${reality_domain}",
        "reality": {
          "enabled": true,
          "public_key": "${public_key}",
          "short_id": "${short_id}"
        }
      }
    }
  ]
}
JSON

  public_ip="$(detect_public_ip || true)"
  cat > "$INFO_FILE" <<TXT
节点类型: ${APP_NAME}
服务器地址: ${public_ip:-请手动填写你的 VPS IP 或域名}
监听端口: ${listen_port}
AnyTLS 密码: ${password}
REALITY 伪装域名: ${reality_domain}
Public Key: ${public_key}
short_id: ${short_id}
服务端配置: ${SERVER_CONFIG}
客户端配置模板: ${CLIENT_CONFIG}
TXT

  backup_existing_singbox_config
  install_server_config_to_singbox "$SERVER_CONFIG"
  validate_singbox_config
  enable_and_restart_service "$SERVICE_NAME"
  open_port_if_possible "$listen_port"

  ok "安装完成"
  show_node_info
}

show_node_info() {
  if [[ ! -f "$INFO_FILE" ]]; then
    warn "未检测到节点信息，请先执行安装。"
    return 1
  fi

  echo
  cat "$INFO_FILE"
  echo
  info "客户端配置模板："
  cat "$CLIENT_CONFIG"
  echo
}

restart_service_action() {
  need_root
  require_service_exists "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"
  ok "已重启 ${SERVICE_NAME}"
}

show_logs_action() {
  require_service_exists "$SERVICE_NAME"
  journalctl -u "$SERVICE_NAME" -n 50 --no-pager
}

uninstall_action() {
  need_root
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^sing-box\.service'; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
  if [[ -f /etc/sing-box/config.json.xnode.bak ]]; then
    cp -f /etc/sing-box/config.json.xnode.bak /etc/sing-box/config.json
    if sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
      systemctl restart sing-box >/dev/null 2>&1 || true
    fi
  fi
  ok "已卸载节点配置，sing-box 保留在系统中。"
}

main_menu() {
  while true; do
    clear
    echo "========== ${APP_NAME} =========="
    echo "1. 安装/重装 AnyTLS + REALITY"
    echo "2. 查看节点信息"
    echo "3. 重启 sing-box"
    echo "4. 查看日志"
    echo "5. 卸载节点配置"
    echo "0. 退出"
    echo
    read -r -p "请输入选项: " choice
    case "$choice" in
      1) install_or_reinstall; press_enter ;;
      2) show_node_info; press_enter ;;
      3) restart_service_action; press_enter ;;
      4) show_logs_action; press_enter ;;
      5) uninstall_action; press_enter ;;
      0) exit 0 ;;
      *) warn "无效选项"; sleep 1 ;;
    esac
  done
}

main_menu
