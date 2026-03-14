# anytls-reality-onekey

极简版 **AnyTLS + REALITY** 一键脚本，目标是：

- 只做一件事：在 Debian / Ubuntu 上快速拉起 sing-box 的 AnyTLS + REALITY 节点
- 交互尽量少：端口、AnyTLS 密码、REALITY 伪装域名、short_id、密钥对
- 不做面板、不做多用户、不做订阅、不做一堆协议混搭
- **仓库只需要 3 个文件：`install.sh`、`xnode.sh`、`README.md`**

## 当前功能

- 安装或重装 AnyTLS + REALITY
- 自动安装 sing-box（按官方安装方式）
- 自动生成或手动填写 REALITY 密钥对
- 生成服务端配置
- 输出客户端 outbound 模板
- 重启服务、查看日志、卸载节点配置

## 支持范围

- Debian 12+
- Ubuntu 22.04+
- systemd
- amd64 / arm64

## 上传到 GitHub

把下面 3 个文件上传到仓库根目录即可：

```text
install.sh
xnode.sh
README.md
```

建议仓库名：

```text
anytls-reality-onekey
```

## 一键安装

把仓库建好后，直接运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/sockc/anytls-reality-onekey/main/install.sh)
```

安装完成后运行：

```bash
xnode
```

## 目录结构

```text
.
├── install.sh
├── xnode.sh
└── README.md
```

## 配置说明

服务端配置最终写入：

```text
/etc/sing-box/config.json
```

同时会在以下目录保留节点信息与客户端模板：

```text
/etc/anytls-reality/
```

## 设计说明

- AnyTLS 入站使用 `users[].password`，不使用 UUID。
- REALITY 服务端使用 `handshake.server`、`private_key`、`short_id[]`。
- 客户端模板使用 `server_name`、`public_key`、`short_id`。
- 默认将“REALITY 伪装域名”同时作为服务端握手目标和客户端 `server_name`。

## 提示

- `install.sh` 只负责把 `xnode.sh` 下载到 `/opt/anytls-reality-onekey/` 并创建 `/usr/local/bin/xnode` 软链接。
- 后续更新脚本时，重新执行一次安装命令即可覆盖本地 `xnode.sh`。
- 如果安装失败，先检查 GitHub 上这 3 个文件是否在仓库根目录，分支是否是 `main`。

## 后续可加

- 自动更新 sing-box
- 备份/恢复
- 输出二维码
- GitHub Release 打包
