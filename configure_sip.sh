#!/bin/bash

# 检查是否提供了IP参数
if [ -z "$1" ]; then
  echo "请提供IP地址作为参数"
  exit 1
fi

IP_ADDRESS="$1"
CONFIG_FILE="/etc/jitsi/videobridge/sip-communicator.properties"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
  echo "错误: 找不到配置文件: $CONFIG_FILE"
  exit 1
fi

# 备份原始配置文件
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"

update_property() {
  local key=$1
  local value=$2
  if grep -q "^${key}=" "$CONFIG_FILE"; then
    # 如果配置项存在，则更新值
    # 使用临时文件来避免 sed 的兼容性问题
    sed "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE" >"${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  else
    # 如果配置项不存在，则添加新配置
    echo "${key}=${value}" >>"$CONFIG_FILE"
  fi
}

# 更新配置,局域网配置项
update_property "org.ice4j.ice.harvest.STUN_MAPPING_HARVESTER_ADDRESSES" ""
update_property "org.ice4j.ice.harvest.NAT_HARVESTER_LOCAL_ADDRESS" "$IP_ADDRESS"
update_property "org.ice4j.ice.harvest.NAT_HARVESTER_PUBLIC_ADDRESS" "$IP_ADDRESS"

echo "SIP 配置文件已更新"

# 重启 jitsi-videobridge2 服务
systemctl restart jitsi-videobridge2

echo "jitsi-videobridge2 服务已重启"
