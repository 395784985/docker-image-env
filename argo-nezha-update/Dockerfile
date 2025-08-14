# 基础镜像用 debian slim，安装 cloudflared + 哪吒
FROM debian:bullseye-slim

# 设置时区和安装依赖
RUN apt-get update && apt-get install -y \
    wget curl unzip supervisor ca-certificates nginx tcpdump \
    && rm -rf /var/lib/apt/lists/*

# 创建目录
RUN mkdir -p /etc/supervisor/conf.d /dashboard/data /etc/nginx/ssl

# 生成自签证书
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/C=CN/ST=Shanghai/L=Shanghai/O=nezha/CN=localhost"

# 安装 cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# 安装哪吒面板
ENV NEZHA_VERSION=v1.12.4
RUN wget https://github.com/nezhahq/nezha/releases/download/${NEZHA_VERSION}/dashboard-linux-amd64.zip \
    && unzip dashboard-linux-amd64.zip -d /dashboard \
    && rm dashboard-linux-amd64.zip \
    && mv /dashboard/dashboard-linux-amd64 /dashboard/nezha-dashboard \
    && chmod +x /dashboard/nezha-dashboard

# Nginx 配置
COPY nginx.conf /etc/nginx/sites-available/default

# Supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 创建日志目录
RUN mkdir -p /var/log/nginx /var/log/nezha && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# 启动 supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
