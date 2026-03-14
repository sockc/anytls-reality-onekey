#!/usr/bin/env bash
set -euo pipefail

REPO_OWNER="${REPO_OWNER:-sockc}"
REPO_NAME="${REPO_NAME:-anytls-reality-onekey}"
REPO_REF="${REPO_REF:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/anytls-reality-onekey}"
BIN_LINK="${BIN_LINK:-/usr/local/bin/xnode}"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}"

need_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "请用 root 运行安装脚本"
    exit 1
  fi
}

fetch() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    echo "未找到 curl 或 wget，无法下载安装文件"
    exit 1
  fi
}

need_root
mkdir -p "$INSTALL_DIR/lib"
fetch "$BASE_URL/xnode.sh" "$INSTALL_DIR/xnode.sh"
fetch "$BASE_URL/lib/common.sh" "$INSTALL_DIR/lib/common.sh"
fetch "$BASE_URL/lib/system.sh" "$INSTALL_DIR/lib/system.sh"
fetch "$BASE_URL/lib/firewall.sh" "$INSTALL_DIR/lib/firewall.sh"
chmod +x "$INSTALL_DIR/xnode.sh"
ln -sf "$INSTALL_DIR/xnode.sh" "$BIN_LINK"

echo "安装完成"
echo "运行命令: xnode"
