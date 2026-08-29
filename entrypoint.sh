#!/bin/sh
set -e

# 端口默认值
NGINX_PORT="${NGINX_PORT:-7001}"      # 对外监听端口
BACKEND_PORT="${BACKEND_PORT:-9000}"  # 后端内部端口

export NGINX_PORT BACKEND_PORT

# 用 envsubst 渲染 nginx 配置（只替换上面两个端口变量，
# 避免误改 nginx 自身的 $host / $http_upgrade 等变量）
envsubst '${NGINX_PORT} ${BACKEND_PORT}' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

# 后台启动 Python 后端
poetry run uvicorn main:app \
    --host 127.0.0.1 \
    --port "${BACKEND_PORT}" &

# 前台运行 nginx（保持容器存活），对外提供前端与 API 代理
exec nginx -g 'daemon off;'