#!/bin/bash
set -e
set -x  # 打印执行命令，便于调试

#############################################
# 变量定义
#############################################
NEZHA_VERSION=${NEZHA_VERSION:-v1.12.4}
ARGO_DOMAIN=${ARGO_DOMAIN:-example.com}
CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN:-}


DASHBOARD_DIR="/dashboard"
CLOUDFLARED_BIN="/usr/local/bin/cloudflared"
SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
SUPERVISOR_CONF="$SUPERVISOR_CONF_DIR/nezha.conf"
NEZHA_NGINX_CONF="/etc/nginx/conf.d/nezha.conf"

export DEBIAN_FRONTEND=noninteractive
export CF_TUNNEL_TOKEN

#############################################
# 安装基础命令
#############################################
# echo "[INFO] Installing basic packages..."
# apt-get update
# apt-get install -y \
#     wget curl unzip tcpdump \
#     awscli tar gzip tzdata openssl sqlite3 coreutils \
#     nginx supervisor
# rm -rf /var/lib/apt/lists/*

#############################################
# 初始化目录
#############################################
mkdir -p "$DASHBOARD_DIR"
mkdir -p /var/log/supervisor
mkdir -p /var/log/nezha

#############################################
# 证书
#############################################
if [ ! -f "$DASHBOARD_DIR/nezha.key" ] || [ ! -f "$DASHBOARD_DIR/nezha.pem" ]; then
  echo "[INFO] Generating self-signed certificate..."
  openssl genrsa -out "$DASHBOARD_DIR/nezha.key" 2048
  openssl req -new -subj "/CN=$ARGO_DOMAIN" \
      -key "$DASHBOARD_DIR/nezha.key" -out "$DASHBOARD_DIR/nezha.csr"
  openssl x509 -req -days 36500 \
      -in "$DASHBOARD_DIR/nezha.csr" -signkey "$DASHBOARD_DIR/nezha.key" \
      -out "$DASHBOARD_DIR/nezha.pem"
  rm "$DASHBOARD_DIR/nezha.csr"
fi

#############################################
# cloudflared
#############################################
if [ ! -f "$CLOUDFLARED_BIN" ]; then
  echo "[INFO] Downloading cloudflared..."
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
      -o "$CLOUDFLARED_BIN"
  chmod +x "$CLOUDFLARED_BIN"
fi

#############################################
# Nezha dashboard
#############################################
if [ ! -f "$DASHBOARD_DIR/nezha-dashboard" ]; then
  echo "[INFO] Downloading Nezha Dashboard..."
  wget -q https://github.com/nezhahq/nezha/releases/download/${NEZHA_VERSION}/dashboard-linux-amd64.zip
  unzip dashboard-linux-amd64.zip -d "$DASHBOARD_DIR"
  rm dashboard-linux-amd64.zip
  mv "$DASHBOARD_DIR/dashboard-linux-amd64" "$DASHBOARD_DIR/nezha-dashboard"
  chmod +x "$DASHBOARD_DIR/nezha-dashboard"
fi

#############################################
# Nginx 配置
#############################################
# if [ ! -f "$NEZHA_NGINX_CONF" ]; then
#   echo "[INFO] Generating default nginx config..."
#   cat > "$NEZHA_NGINX_CONF" <<EOF
# server {
#     listen 443 ssl;
#     listen [::]:443 ssl;
#     http2 on; # Nginx > 1.25.1，请注释上面两行，启用此行
#     server_name ${ARGO_DOMAIN:-'localhost'}; # 替换为你的域名

#     # 自签证书配置
#     ssl_certificate          /dashboard/nezha.pem; # 域名证书路径
#     ssl_certificate_key      /dashboard/nezha.key;       # 域名私钥路径
#     ssl_session_timeout 1d;
#     ssl_session_cache shared:SSL:10m; # 如果与其他配置冲突，请注释此项
#     ssl_protocols TLSv1.2 TLSv1.3;

#     underscores_in_headers on;
#     set_real_ip_from 0.0.0.0/0; # 替换为你的 CDN 回源 IP 地址段
#     real_ip_header CF-Connecting-IP; # 替换为你的 CDN 提供的私有 header，此处为 CloudFlare 默认
#     # 如果你使用nginx作为最外层，把上面两行注释掉

#     # grpc 相关    
#     location ^~ /proto.NezhaService/ {
#         grpc_set_header Host $host;
#         grpc_set_header nz-realip $http_CF_Connecting_IP; # 替换为你的 CDN 提供的私有 header，此处为 CloudFlare 默认
#         #grpc_set_header nz-realip $remote_addr; # 如果你使用nginx作为最外层，就把上面一行注释掉，启用此行
#         grpc_read_timeout 600s;
#         grpc_send_timeout 600s;
#         grpc_socket_keepalive on;
#         client_max_body_size 10m;
#         grpc_buffer_size 4m;
#         grpc_pass grpc://dashboard;
#     }

#      # websocket 相关
#     location ~* ^/api/v1/ws/(server|terminal|file)(.*)$ {
#         proxy_set_header Host $host;
#         proxy_set_header nz-realip $http_cf_connecting_ip; # 替换为你的 CDN 提供的私有 header，此处为 CloudFlare 默认
#         # proxy_set_header nz-realip $remote_addr; # 如果你使用nginx作为最外层，就把上面一行注释掉，启用此行
#         proxy_set_header Origin https://$host;
#         proxy_set_header Upgrade $http_upgrade;
#         proxy_set_header Connection "upgrade";
#         proxy_read_timeout 3600s;
#         proxy_send_timeout 3600s;
#         proxy_pass http://localhost:8008;
#     }
#     # web
#     location / {
#         proxy_set_header Host $host;
#         proxy_set_header nz-realip $http_cf_connecting_ip; # 替换为你的 CDN 提供的私有 header，此处为 CloudFlare 默认
#         # proxy_set_header nz-realip $remote_addr; # 如果你使用nginx作为最外层，就把上面一行注释掉，启用此行
#         proxy_read_timeout 3600s;
#         proxy_send_timeout 3600s;
#         proxy_buffer_size 128k;
#         proxy_buffers 4 256k;
#         proxy_busy_buffers_size 256k;
#         proxy_max_temp_file_size 0;
#         proxy_pass http://localhost:8008;
#     }

#     #access_log  /dev/null;
#     #error_log   /dev/null;
# }

# upstream dashboard {
#     server 127.0.0.1:8008;
#     keepalive 512;
# }
# EOF
# fi

#############################################
# Supervisor 配置
#############################################
if [ ! -f "$SUPERVISOR_CONF" ]; then
  echo "[INFO] Generating supervisor config..."
  cat > "$SUPERVISOR_CONF" <<EOF
[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:cloudflared]
command=cloudflared tunnel --no-autoupdate run --protocol http2 --token "%(ENV_CF_TUNNEL_TOKEN)s"
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:nezha]
command=$DASHBOARD_DIR/nezha-dashboard
directory=$DASHBOARD_DIR
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

EOF
fi

#############################################
# 启动 supervisord
#############################################
echo "[START] Launching supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
