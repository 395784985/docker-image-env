#!/bin/bash
set -euo pipefail

# ========== 配置区域 (可通过环境变量覆盖) ==========

# 协议开关 (true/false)
ENABLE_VLESS=${ENABLE_VLESS:-true}
ENABLE_TUNNEL=${ENABLE_TUNNEL:-true}
ENABLE_HYSTERIA2=${ENABLE_HYSTERIA2:-true}

# 伪装域名 / 服务器域名 (如未指定，脚本将使用本机 IP)
REALITY_DOMAIN=${REALITY_DOMAIN:-}
HYSTERIA_DOMAIN=${HYSTERIA_DOMAIN:-}

# 端口设置 (如未指定，自动随机)
VLESS_PORT=${VLESS_PORT:-}
HYSTERIA_PORT=${HYSTERIA_PORT:-}

# Cloudflare 隧道环境变量 (固定隧道使用)
CF_TOKEN=${CF_TOKEN:-}
CF_TUNNEL_ID=${CF_TUNNEL_ID:-}
ARGO_DOMAIN=${ARGO_DOMAIN:-}  # 固定隧道的域名 (由 Cloudflare 隧道配置)

# Hysteria2 用户名密码及流控 (默认为单用户，可通过环境变量覆盖)
HYSTERIA_USER=${HYSTERIA_USER:-user}
HYSTERIA_PASS=${HYSTERIA_PASS:-$(head -c8 /dev/urandom | md5sum | cut -d' ' -f1)}
HYSTERIA_UP=${HYSTERIA_UP:-100}
HYSTERIA_DOWN=${HYSTERIA_DOWN:-100}

# 安装目录
SB_DIR="/opt/singbox"
CF_DIR="/opt/cloudflared"
LOG_DIR="$SB_DIR/log"

# ========== 函数定义 ==========

# 检测系统类型并安装依赖
install_dependencies() {
    echo "检测并安装依赖..."
    if [ -f /etc/os-release ]; then . /etc/os-release; fi
    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get install -y curl wget tar iproute2 ca-certificates jq
    elif command -v yum >/dev/null; then
        yum install -y epel-release && yum update -y
        yum install -y curl wget tar iproute socat jq
    elif command -v dnf >/dev/null; then
        dnf install -y curl wget tar iproute socat jq
    elif command -v apk >/dev/null; then
        apk update
        apk add curl wget tar iproute2 jq
    else
        echo "Unsupported package manager. 请手动安装 curl, wget, tar, jq 等依赖." >&2
        exit 1
    fi
}

# 获取本机主 IP
get_local_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [ -z "$ip" ] && ip=$(ip addr | awk '/inet /{print $2}' | grep -Eo '([0-9]+\.){3}[0-9]+' | grep -v '^127\.' | head -n1)
    echo "${ip:-127.0.0.1}"
}

# 随机可用端口 (1025-65535)
random_port() {
    local port
    while :; do
        port=$((RANDOM % 55000 + 1025))
        ss -nutl | grep -q ":$port " || break
    done
    echo $port
}

# 下载并安装最新 Sing-box
install_singbox() {
    echo "安装 Sing-box 到 $SB_DIR ..."
    mkdir -p "$SB_DIR"
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) sb_arch="amd64";;
        aarch64|arm64) sb_arch="arm64";;
        armv7*|armv6*) sb_arch="armv7";;
        i?86) sb_arch="386";;
        *) echo "不支持的架构: $arch"; exit 1;;
    esac
    local latest
    latest=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | jq -r .tag_name)
    latest=${latest#v}
    local url="https://github.com/SagerNet/sing-box/releases/download/v${latest}/sing-box-${latest}-linux-${sb_arch}.tar.gz"
    wget -qO- "$url" | tar -xz -C "$SB_DIR"
    chmod +x "$SB_DIR/sing-box"
}

# 下载并安装最新 Cloudflared
install_cloudflared() {
    echo "安装 cloudflared 到 $CF_DIR ..."
    mkdir -p "$CF_DIR"
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) cf_arch="amd64";;
        aarch64|arm64) cf_arch="arm64";;
        armv7*|armv6*) cf_arch="armhf";;
        i?86) cf_arch="386";;
        *) echo "不支持的架构: $arch"; exit 1;;
    esac
    local latest
    latest=$(curl -s "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep '"tag_name":' | head -n1 | cut -d\" -f4)
    latest=${latest#v}
    local file="cloudflared-linux-$cf_arch"
    local url="https://github.com/cloudflare/cloudflared/releases/download/$latest/$file"
    wget -qO "$CF_DIR/cloudflared" "$url"
    chmod +x "$CF_DIR/cloudflared"
}

# 生成 Sing-box 配置
generate_singbox_config() {
    mkdir -p "$LOG_DIR"
    echo "生成 Sing-box 配置..."

    # 基础变量
    uuid=$(cat /proc/sys/kernel/random/uuid)
    [ -z "$VLESS_PORT" ] && VLESS_PORT=$(random_port)
    [ -z "$HYSTERIA_PORT" ] && HYSTERIA_PORT=$(random_port)
    [ -z "$VMESS_PORT" ] && VMESS_PORT=$(random_port)

    # 生成 Reality 密钥对
    key_pair=$($SB_DIR/sing-box generate reality-keypair)
    private_key=$(echo "$key_pair" | grep PrivateKey | awk '{print $2}')
    public_key=$(echo "$key_pair" | grep PublicKey | awk '{print $2}')

    # 生成配置文件头
    cat > "$SB_DIR/config.json" <<EOF
{
  "log": {
    "disabled": false,
    "level": "error",
    "output": "$LOG_DIR/sb.log",
    "timestamp": true
  },
  "inbounds": [
EOF

    first=true

    # VLESS Reality
    if [ "$ENABLE_VLESS" = true ]; then
        $first || echo "," >> "$SB_DIR/config.json"
        first=false
        cat >> "$SB_DIR/config.json" <<EOF
    {
      "tag": "vless-reality",
      "type": "vless",
      "listen": "::",
      "listen_port": $VLESS_PORT,
      "users": [
        { "uuid": "$uuid", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.iij.ad.jp",
        "reality": {
          "enabled": true,
          "handshake": { "server": "www.iij.ad.jp", "server_port": 443 },
          "private_key": "$private_key",
          "short_id": [ "" ]
        }
      }
    }
EOF
    fi

    # Hysteria2
    if [ "$ENABLE_HYSTERIA2" = true ]; then
        $first || echo "," >> "$SB_DIR/config.json"
        first=false
        cat >> "$SB_DIR/config.json" <<EOF
    {
      "tag": "hysteria2",
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $HYSTERIA_PORT,
      "users": [ { "password": "$uuid" } ],
      "tls": {
        "enabled": true,
        "alpn": [ "h3" ],
        "certificate_path": "$SB_DIR/cert.pem",
        "key_path": "$SB_DIR/private.key"
      }
    }
EOF
    fi

    # VMess + Argo (Cloudflared)
    if [ "$ENABLE_TUNNEL" = true ]; then
        $first || echo "," >> "$SB_DIR/config.json"
        first=false
        cat >> "$SB_DIR/config.json" <<EOF
    {
      "tag": "vmess-argo",
      "type": "vmess",
      "listen": "127.0.0.1",
      "listen_port": $VMESS_PORT,
      "users": [
        { "uuid": "$uuid" }
      ]
    }
EOF
    fi

    # 配置文件尾
    cat >> "$SB_DIR/config.json" <<EOF
  ],
  "outbounds": [
    { "tag": "direct", "type": "direct" },
    { "tag": "block", "type": "block" }
  ]
}
EOF
}



# 生成 systemd 服务 (Sing-box)
setup_systemd_singbox() {
    echo "创建 Sing-box systemd 服务..."
    cat > /etc/systemd/system/singbox.service <<EOF
[Unit]
Description=Sing-box Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$SB_DIR/sing-box run -c $SB_DIR/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable singbox
}

# 生成 systemd 服务 (Cloudflared Tunnel)
setup_systemd_cloudflared() {
    if [ "$ENABLE_TUNNEL" != true ]; then return; fi
    echo "创建 cloudflared systemd 服务..."
    local exec_cmd
    if [ -n "$CF_TOKEN" ] ; then
        exec_cmd="$CF_DIR/cloudflared tunnel run --token $CF_TOKEN $CF_TUNNEL_ID"
    else
        # 使用随机隧道模式，将流量转发到 Sing-box VLESS 端口
        exec_cmd="$CF_DIR/cloudflared tunnel --no-autoupdate --url http://localhost:$VLESS_PORT"
    fi
    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflared Tunnel Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$exec_cmd
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable cloudflared
}

# 设置 logrotate 限制日志大小
setup_logrotate() {
    echo "配置 logrotate 限制日志大小..."
    cat > /etc/logrotate.d/singbox <<EOF
$LOG_DIR/*.log {
    daily
    rotate 5
    size 10M
    missingok
    notifempty
    compress
    copytruncate
}
EOF
}

# 卸载功能
uninstall_all() {
    echo "正在卸载 Sing-box 服务..."
    systemctl stop singbox.service 2>/dev/null || true
    systemctl disable singbox.service 2>/dev/null || true
    rm -f /etc/systemd/system/singbox.service
    echo "正在卸载 cloudflared 服务..."
    systemctl stop cloudflared.service 2>/dev/null || true
    systemctl disable cloudflared.service 2>/dev/null || true
    rm -f /etc/systemd/system/cloudflared.service
    systemctl daemon-reload
    echo "删除安装目录..."
    rm -rf "$SB_DIR" "$CF_DIR"
    rm -f /etc/logrotate.d/singbox
    echo "卸载完成。"
    exit 0
}

# ========== 主程序 ==========

if [[ "${1:-}" == "uninstall" ]] || [[ "${UNINSTALL:-}" == "true" ]]; then
    uninstall_all
fi

install_dependencies
install_singbox
install_cloudflared
generate_singbox_config
setup_systemd_singbox
if [ "$ENABLE_TUNNEL" = true ]; then
    setup_systemd_cloudflared
fi
setup_logrotate

echo "安装完成！Sing-box 服务已设置为开机自启，并监听如下端口："
$ENABLE_VLESS && echo "  - VLESS+REALITY: $VLESS_PORT (域名 $REALITY_DOMAIN)"
$ENABLE_HYSTERIA2 && echo "  - Hysteria2: $HYSTERIA_PORT (域名 $HYSTERIA_DOMAIN, 用户 $HYSTERIA_USER)"
$ENABLE_TUNNEL && echo "  - Cloudflared 隧道: $( [ -n "$CF_TUNNEL_ID" ] && echo "固定隧道 ($CF_TUNNEL_ID)" || echo "随机隧道 (启动后在日志中查看子域)")"
echo "日志路径：$LOG_DIR/sing-box.log"
