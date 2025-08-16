# 使用 nginx alpine 作为基础镜像
FROM nginx:stable-alpine

# 设置时区环境变量
ENV TZ=Asia/Shanghai

# 安装必要的系统工具和依赖
RUN apk add --no-cache \
    wget curl unzip supervisor ca-certificates tcpdump \
    aws-cli tar gzip tzdata openssl sqlite coreutils

# 创建目录
RUN mkdir -p /etc/supervisor/conf.d /dashboard/data /etc/nginx/ssl

# 生成 nezha 证书
ENV ARGO_DOMAIN=${ARGO_DOMAIN:-example.com}
RUN openssl genrsa -out /dashboard/nezha.key 2048 && \
    openssl req -new -subj "/CN=${ARGO_DOMAIN}" -key /dashboard/nezha.key -out /dashboard/nezha.csr && \
    openssl x509 -req -days 36500 -in /dashboard/nezha.csr -signkey /dashboard/nezha.key -out /dashboard/nezha.pem

# 安装 cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# 安装哪吒面板
ENV NEZHA_VERSION=${NEZHA_VERSION:-v1.12.4}
RUN wget https://github.com/nezhahq/nezha/releases/download/${NEZHA_VERSION}/dashboard-linux-amd64.zip \
    && unzip dashboard-linux-amd64.zip -d /dashboard \
    && rm dashboard-linux-amd64.zip \
    && mv /dashboard/dashboard-linux-amd64 /dashboard/nezha-dashboard \
    && chmod +x /dashboard/nezha-dashboard

# 安装 哪吒应用文件 
# COPY --from=ghcr.io/nezhahq/nezha:v1.12.4 /dashboard/app /dashboard/nezha-dashboard
# COPY --from=ghcr.io/nezhahq/nezha:v1.12.4 /etc/ssl/certs /etc/ssl/certs

# Nginx 配置
COPY nginx.conf /etc/nginx/conf.d/main.conf

# Supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 创建日志目录
RUN mkdir -p /var/log/nginx /var/log/nezha && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# 启动 supervisord
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
