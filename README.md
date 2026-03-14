# anytls-reality-onekey

极简版 **AnyTLS + REALITY** 一键脚本，目标是：

- 只做一件事：在 Debian / Ubuntu 上快速拉起 sing-box 的 AnyTLS + REALITY 节点
- 交互尽量少：端口、AnyTLS 密码、REALITY 伪装域名、short_id、密钥对
- 不做面板、不做多用户、不做订阅、不做一堆协议混搭

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

- REALITY 服务端使用 `handshake.server`、`private_key`、`short_id[]`。
- 客户端模板使用 `server_name`、`public_key`、`short_id`。
- 默认将“REALITY 伪装域名”同时作为服务端握手目标和客户端 `server_name`。



