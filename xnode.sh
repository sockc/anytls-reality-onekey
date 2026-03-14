#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AnyTLS + REALITY"
WORK_DIR="/etc/anytls-reality"
SERVER_CONFIG="${WORK_DIR}/server.json"
CLIENT_CONFIG="${WORK_DIR}/client-outbound.json"
INFO_FILE="${WORK_DIR}/node-info.txt"
SERVICE_NAME="sing-box"
DEFAULT_PORT="443"
DEFAULT_REALITY_DOMAIN="www.cloudflare.com"

color() {
  local code="$1" text="$2"
  printf '\033[%sm%s\033[0m\n' "$code" "$text"
}

ok() { color '32' "[OK] $*"; }
warn() { color '33' "[WARN] $*"; }
err() { color '31' "[ERR] $*"; }
info() { color '36' "[INFO] $*"; }
die() { err "$*"; exit 1; }

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    die "请使用 root 运行。"
  fi
}

press_enter() {
  read -r -p "按回车继续..." _
}

prompt_with_default() {
  local message="$1" default_value="$2" input
  read -r -p "${message} [默认 ${default_value}]: " input
  printf '%s' "${input:-$default_value}"
}

prompt_required() {
  local message="$1" input
  while true; do
    read -r -p "${message}: " input
    [[ -n "$input" ]] && { printf '%s' "$input"; return 0; }
    warn "不能为空。"
  done
}

random_alnum() {
  local len="$1"
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
}

random_hex() {
  local bytes="$1"
  openssl rand -hex "$bytes"
}

prompt_or_random() {
  local message="$1" len="$2" input generated
  read -r -p "${message}: " input
  if [[ -n "$input" ]]; then
    printf '%s' "$input"
  else
    generated="$(random_alnum "$len")"
    printf '%s' "$generated"
  fi
}

port_in_use() {
  local port="$1"
  ss -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "(^|[\]:])${port}$"
}

prompt_port() {
  local message="$1" default_port="$2" port
  while true; do
    port="$(prompt_with_default "$message" "$default_port")"
    [[ "$port" =~ ^[0-9]+$ ]] || { warn "端口必须是数字。"; continue; }
    (( port >= 1 && port <= 65535 )) || { warn "端口范围必须在 1-65535。"; continue; }
    if port_in_use "$port"; then
      warn "端口 ${port} 已被占用，请换一个。"
      continue
    fi
    printf '%s' "$port"
    return 0
  done
}

prompt_short_id() {
  local message="$1" input
  read -r -p "${message}: " input
  if [[ -z "$input" ]]; then
    printf '%s' "$(random_hex 4)"
    return 0
  fi
  if [[ ! "$input" =~ ^[0-9a-fA-F]{2,16}$ ]] || (( ${#input} % 2 != 0 )); then
    die "short_id 必须是 2-16 位十六进制字符，且长度必须为偶数。"
  fi
  printf '%s' "$input"
}

ensure_basic_tools() {
  local missing=()
  for bin in systemctl ss openssl awk sed grep; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  if ((${#missing[@]} > 0)); then
    die "缺少必要命令: ${missing[*]}"
  fi
}

ensure_supported_os() {
  [[ -r /etc/os-release ]] || die "无法识别系统。"
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) die "当前仅支持 Debian / Ubuntu。" ;;
  esac
}

backup_existing_singbox_config() {
  mkdir -p /etc/sing-box
  if [[ -f /etc/sing-box/config.json ]]; then
    cp -f /etc/sing-box/config.json /etc/sing-box/config.json.xnode.bak
  fi
}

install_server_config_to_singbox() {
  local src="$1"
  mkdir -p /etc/sing-box
  cp -f "$src" /etc/sing-box/config.json
}

validate_singbox_config() {
  sing-box check -c /etc/sing-box/config.json >/dev/null
}

require_service_exists() {
  local service="$1"
  command -v systemctl >/dev/null 2>&1 || die "当前系统没有 systemctl。"
  systemctl list-unit-files | grep -q "^${service}\.service" || die "未检测到 ${service} 服务。"
}

create_singbox_systemd_service() {
  local bin_path
  bin_path="$(command -v sing-box || true)"
  [[ -n "$bin_path" ]] || die "未找到 sing-box 可执行文件。"
  mkdir -p /etc/systemd/system
  cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org/
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${bin_path} run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3
LimitNOFILE=infinity
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  ok "已创建 ${SERVICE_NAME}.service"
}

ensure_singbox_service() {
  command -v systemctl >/dev/null 2>&1 || die "当前系统没有 systemctl。"
  if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}\.service"; then
    warn "未检测到 ${SERVICE_NAME}.service，正在自动创建。"
    create_singbox_systemd_service
  fi
}

enable_and_restart_service() {
  local service="$1"
  ensure_singbox_service
  systemctl daemon-reload
  systemctl enable "$service" >/dev/null 2>&1 || true
  systemctl restart "$service"
}

fetch_text() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    return 1
  fi
}

detect_public_ip() {
  local ip
  ip="$(fetch_text "https://api.ipify.org" 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(fetch_text "https://ipv4.icanhazip.com" 2>/dev/null || true)"
  fi
  printf '%s' "${ip//$'\n'/}"
}

ensure_singbox_installed() {
  if command -v sing-box >/dev/null 2>&1; then
    ok "已检测到 sing-box: $(sing-box version | head -n 1)"
    return 0
  fi

  info "未检测到 sing-box，开始按官方方式安装。"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://sing-box.app/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://sing-box.app/install.sh | sh
  else
    die "未找到 curl 或 wget，无法安装 sing-box。"
  fi

  command -v sing-box >/dev/null 2>&1 || die "sing-box 安装失败。"
  ok "sing-box 安装完成。"
}

open_port_if_possible() {
  local port="$1"

  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${port}/tcp" >/dev/null 2>&1 || true
    ok "已尝试通过 UFW 放行 ${port}/tcp"
    return 0
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    ok "已尝试通过 firewalld 放行 ${port}/tcp"
    return 0
  fi

  warn "未检测到 UFW 或 firewalld，请自行检查云防火墙/安全组。"
}

install_or_reinstall() {
  need_root
  ensure_supported_os
  ensure_basic_tools
  ensure_singbox_installed

  mkdir -p "$WORK_DIR"

  local listen_port password reality_domain short_id key_answer key_pair private_key public_key public_ip

  listen_port="$(prompt_port "请输入监听端口" "$DEFAULT_PORT")"
  password="$(prompt_or_random "请输入 AnyTLS 密码（留空自动生成）" 24)"
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
        "server_name": "${reality_domain}",
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
  if [[ -f "$CLIENT_CONFIG" ]]; then
    info "客户端配置模板："
    cat "$CLIENT_CONFIG"
    echo
  fi
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
