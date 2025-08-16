FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 安装依赖
RUN apt-get update && apt-get install -y \
    wget curl unzip  \
    # awscli tar gzip tzdata openssl sqlite3 coreutils tcpdump \
    nginx \
    supervisor \
 && rm -rf /var/lib/apt/lists/*

# 创建必要目录
RUN mkdir -p /dashboard /var/log/nezha /var/log/supervisor

# 拷贝入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 设置工作目录
WORKDIR /dashboard

# Nginx 配置
COPY nginx.conf /etc/nginx/conf.d/main.conf

# Supervisor 配置
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# 暴露端口
EXPOSE 8008

# 配置环境变量
ENV ARGO_DOMAIN="" \
    CF_TUNNEL_TOKEN=""

# 设置容器启动命令
CMD ["/entrypoint.sh"]