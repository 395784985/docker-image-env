# 使用 nginx alpine 作为基础镜像
FROM nginx:stable-alpine

# 设置时区环境变量
ENV TZ=Asia/Shanghai

# 安装必要的系统工具和依赖
RUN apk add --no-cache \
    aws-cli \
    tar \
    gzip \
    tzdata \
    openssl \
    sqlite \
    coreutils

# 配置工作目录
WORKDIR /dashboard

# 创建数据目录并设置权限
RUN mkdir -p /dashboard/data && chmod -R 777 /dashboard

# 安装 哪吒应用文件 
COPY --from=ghcr.io/nezhahq/nezha:v1.12.4 /dashboard/app /dashboard/app
COPY --from=ghcr.io/nezhahq/nezha:v1.12.4 /etc/ssl/certs /etc/ssl/certs

# 安装 Cloudflare 隧道工具
COPY --from=cloudflare/cloudflared:latest /usr/local/bin/cloudflared /usr/local/bin/cloudflared

# 配置 Nginx
COPY main.conf /etc/nginx/conf.d/main.conf

# 设置网络端口
EXPOSE 8008

# 配置环境变量
ENV ARGO_DOMAIN="" \
    CF_TOKEN="" \
    R2_ACCESS_KEY_ID="" \
    R2_BUCKET_NAME="" \
    R2_ENDPOINT_URL="" \
    R2_SECRET_ACCESS_KEY=""

# 复制启动和备份脚本
COPY backup.sh /backup.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /backup.sh && chmod +x /entrypoint.sh

# 设置容器启动命令
CMD ["/entrypoint.sh"]
