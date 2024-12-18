# 检查是否提供了IP参数
if [ $# -ne 1 ]; then
  echo "用法: $0 <IP地址>"
  exit 1
fi

IP_ADDRESS=$1
CONFIG_DIR="/etc/jitsi/videobridge"
JVB_CONF="$CONFIG_DIR/jvb.conf"
TEMP_CONF="/tmp/jvb.conf.tmp"

# 创建临时配置文件
# health配置项需要取消校验
cat >"$TEMP_CONF" <<EOF
videobridge {
    http-servers {
        public {
            port = 9090
        }
    }
    websockets {
        enabled = true
        domain = "$IP_ADDRESS:443"
        tls = true
    }
    health {
        require-valid-address = false
    }
}
EOF

# 检查配置目录是否存在
if [ ! -d "$CONFIG_DIR" ]; then
  echo "错误: 配置目录 $CONFIG_DIR 不存在"
  rm "$TEMP_CONF"
  exit 1
fi

# 备份原始配置文件(如果存在)
if [ -f "$JVB_CONF" ]; then
  cp "$JVB_CONF" "${JVB_CONF}.backup"
fi

# 移动新配置文件到目标位置
mv "$TEMP_CONF" "$JVB_CONF"
chown jvb:jitsi "$JVB_CONF"
chmod 644 "$JVB_CONF"

echo "JVB配置文件已更新"

# 重启jitsi-videobridge2服务
systemctl restart jitsi-videobridge2

echo "jitsi-videobridge2服务已重启"
