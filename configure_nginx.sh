#!/bin/bash

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用sudo运行此脚本"
    exit 1
fi

# 检查是否传入了 IP 参数
if [ -z "$1" ]; then
  echo "请提供服务器的 IP 地址。用法: ./configure_nginx.sh <server-ip>"
  exit 1
fi

SERVER_IP=$1
NGINX_CONF="/etc/nginx/sites-available/$SERVER_IP.conf"
BACKUP_CONF="${NGINX_CONF}.backup"
CURRENT_DIR=$(pwd)  # 获取当前目录

# 检查配置文件是否存在
if [ ! -f "$NGINX_CONF" ]; then
    echo "错误：配置文件 $NGINX_CONF 不存在"
    exit 1
fi

# 创建备份
cp "$NGINX_CONF" "$BACKUP_CONF"
echo "已创建配置文件备份：$BACKUP_CONF"

# 要插入的新配置内容，使用当前目录
NEW_LOCATION="    location ~ ^/room-web/(.*)$ {\n        add_header 'Access-Control-Allow-Origin' '*';\n        root $CURRENT_DIR;\n        try_files \$uri \$uri/ /room-web/index.html last;\n        index index.html;\n    }"

# 使用sed插入新配置
sed -i "/include \/etc\/jitsi\/meet\/jaas\/\*\.conf;/i $NEW_LOCATION" "$NGINX_CONF"

# 检查修改是否成功
if [ $? -eq 0 ]; then
    echo "配置文件修改成功"
    
    # 测试nginx配置
    nginx -t
    if [ $? -eq 0 ]; then
        echo "Nginx配置测试通过"
        sleep 2
        # 重新加载nginx配置
        systemctl reload nginx
        if [ $? -eq 0 ]; then
            echo "Nginx配置已重新加载"
        else
            echo "错误：Nginx配置重新加载失败"
            # 还原备份
            cp "$BACKUP_CONF" "$NGINX_CONF"
            exit 1
        fi
    else
        echo "错误：Nginx配置测试失败"
        # 还原备份
        cp "$BACKUP_CONF" "$NGINX_CONF"
        exit 1
    fi
else
    echo "错误：配置文件修改失败"
    # 还原备份
    cp "$BACKUP_CONF" "$NGINX_CONF"
    exit 1
fi