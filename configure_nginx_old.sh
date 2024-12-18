#!/bin/bash

# 检查是否传入了 IP 参数
if [ -z "$1" ]; then
  echo "请提供服务器的 IP 地址。用法: ./configure_nginx.sh <server-ip>"
  exit 1
fi

SERVER_IP=$1
SCRIPT_DIR=$(pwd)                     # 获取脚本所在目录
NGINX_CONF="$SCRIPT_DIR/webview.conf" # Nginx 配置文件路径
SSL_CERT_DIR="/etc/jitsi/meet"        # SSL 证书目录
DIST_DIR="$SCRIPT_DIR/dist"           # Vite 项目的打包文件目录
WEBVIEW_PATH="/etc/nginx/web-meeting" # Web服务静态文件目录

# SSL 证书和私钥路径
SSL_CERT="$SSL_CERT_DIR/$SERVER_IP.crt"
SSL_KEY="$SSL_CERT_DIR/$SERVER_IP.key"

# 检查证书文件是否存在
if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
  echo "证书或私钥文件不存在，请检查路径和文件名：$SSL_CERT 和 $SSL_KEY"
  exit 1
fi

# 检查并处理 web-meeting 目录
if [ -d "$WEBVIEW_PATH" ]; then
  echo "删除现有的 web-meeting 目录"
  sudo rm -rf "$WEBVIEW_PATH"
fi

# 创建新的 web-meeting 目录
echo "创建新的 web-meeting 目录"
sudo mkdir -p "$WEBVIEW_PATH"

# 检查并设置 update_webip.sh 的执行权限
UPDATE_WEBIP_SCRIPT="$SCRIPT_DIR/update_webip.sh"
if [ ! -x "$UPDATE_WEBIP_SCRIPT" ]; then
  echo "设置 update_webip.sh 的执行权限"
  sudo chmod +x "$UPDATE_WEBIP_SCRIPT"
fi

# 执行 update_webip.sh 脚本
echo "执行 update_webip.sh 脚本"
"$UPDATE_WEBIP_SCRIPT" "$SERVER_IP"

# 复制 dist 目录内容到 web-meeting
echo "复制 dist 目录内容到 web-meeting"
sudo cp -r "$DIST_DIR"/* "$WEBVIEW_PATH/"

ENABLED_CONF="/etc/nginx/sites-enabled/webview.conf"

if [ -f "$ENABLED_CONF" ]; then
  echo "删除现有的配置文件：$ENABLED_CONF"
  sudo rm -f "$ENABLED_CONF"
fi

sleep 5

# 设置目录权限
echo "设置目录权限"
sudo chmod -R 755 "$WEBVIEW_PATH"

sudo chmod 755 "$NGINX_CONF"

# 创建 Nginx 配置文件
cat >"$NGINX_CONF" <<EOL
server {
        listen 1443 ssl;
        server_name $SERVER_IP;
            ssl_certificate $SSL_CERT;
            ssl_certificate_key $SSL_KEY;
            ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
            ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
            ssl_prefer_server_ciphers on;
        root $WEBVIEW_PATH;
        location /room {
                gzip_static on;
                try_files $uri $uri/ /index.html;
        }
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOL

# 将生成的配置文件复制到 /etc/nginx/sites-enabled/
sudo cp "$NGINX_CONF" "$ENABLED_CONF"

# 检查 Nginx 配置语法是否正确
sudo nginx -t
if [ $? -ne 0 ]; then
  echo "Nginx 配置有误，退出！"
  exit 1
fi

sleep 5

# 重启 Nginx 使配置生效
sudo systemctl reload nginx

echo "Nginx 配置已更新，并且重启成功！"
