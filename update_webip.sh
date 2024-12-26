#!/bin/bash

# 检查是否提供了 IP 参数
if [ $# -ne 1 ]; then
  echo "使用方法: $0 <IP地址>"
  exit 1
fi

IP=$1
FILE="room-web/index.html"

# 使用 sed 命令替换 IP 地址
sed -i "s|https://[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/external_api\.js|https://$IP/external_api.js|" $FILE

if [ $? -eq 0 ]; then
  echo "IP 地址已成功更新为: $IP"
else
  echo "更新失败"
fi
