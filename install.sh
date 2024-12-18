#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 检查并卸载已安装的 Jitsi Meet
check_and_uninstall_jitsi() {
  echo "检查是否已安装 Jitsi Meet..."

  # 检查是否存在任意 Jitsi 相关包
  if dpkg -l | grep -qE "jitsi-meet|jicofo|jitsi-videobridge2|jigasi|prosody"; then
    echo "检测到已安装的 Jitsi Meet 组件"
    read -p "是否卸载现有安装？[Y/n] " response
    response=${response:-Y}

    if [[ $response =~ ^[Yy]$ ]]; then
      echo "正在卸载 Jitsi Meet 及其所有组件..."
      apt purge -y jigasi jitsi-meet jitsi-meet-web-config \
        jitsi-meet-prosody jitsi-meet-turnserver \
        jitsi-meet-web jicofo jitsi-videobridge2

      # 清理残留配置文件和目录
      rm -rf /usr/share/jitsi-meet* /usr/share/jicofo* /usr/share/jitsi-videobridge*
      rm -rf /etc/jitsi
      rm -rf /opt/jitsi

      # 清理可能的 prosody 配置
      rm -rf /etc/prosody/conf.d/*meet*

      echo "Jitsi Meet 已完全卸载"
    else
      echo "用户选择保留现有安装，退出脚本"
      exit 0
    fi
  else
    echo "未检测到现有的 Jitsi Meet 安装，继续安装流程..."
  fi
}

# 验证 IP 地址格式的函数
validate_ip() {
  local ip=$1
  if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    # 检查每个IP段是否在有效范围内
    for octet in $(echo $ip | tr '.' ' '); do
      if [[ $octet -lt 0 || $octet -gt 255 ]]; then
        return 1
      fi
    done
    return 0
  else
    return 1
  fi
}

# 获取系统IP地址的函数
get_system_ip() {
  # 尝试多种方法获取IP地址

  # 方法1: ip addr 命令
  local ip=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -n 1)

  # 如果方法1失败,尝试方法2: hostname 命令
  if [ -z "$ip" ]; then
    ip=$(hostname -I | awk '{print $1}')
  fi

  # 如果方法2失败,尝试方法3: curl 外部服务
  if [ -z "$ip" ]; then
    ip=$(curl -s ifconfig.me)
  fi

  echo "$ip"
}

# 检查并安装必要的工具
check_and_install_tools() {
  local tools=("curl" "apt-transport-https" "debconf-utils")
  for tool in "${tools[@]}"; do
    if ! command -v $tool &>/dev/null; then
      echo "正在安装 $tool..."
      apt-get install -y $tool >/dev/null 2>&1
    fi
  done
}

# 检查并确保 nginx 正常运行
configure_webview_nginx() {
  echo "检查 nginx 服务状态..."

  # 检查 nginx 是否已安装
  if ! command -v nginx &>/dev/null; then
    echo "nginx 未安装，正在安装..."
    apt-get install -y nginx
  fi

  if [ -f "./configure_nginx.sh" ]; then
    echo "正在配置 nginx..."
    bash ./configure_nginx.sh "$1"
  fi

  # 验证 nginx 是否正在运行
  if ! systemctl is-active --quiet nginx; then
    echo "nginx 服务启动失败，查看日志..."
    journalctl -xe --unit=nginx
    exit 1
  fi

  echo "nginx 服务运行正常"
}

# 检查防火墙设置
check_firewall() {
  echo "检查防火墙设置..."

  # 如果系统使用 ufw
  if command -v ufw &>/dev/null; then
    echo "配置 ufw 防火墙规则..."
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 10000/udp
    ufw allow 22/tcp
    ufw --force enable
  fi
}

# 设置服务开机自启
configure_autostart() {
  echo "配置服务开机自启动..."

  # 配置所有相关服务开机自启
  systemctl enable nginx
  systemctl enable prosody
  systemctl enable jicofo
  systemctl enable jitsi-videobridge2

  # 确保服务当前是启动的
  systemctl start nginx
  systemctl start prosody
  systemctl start jicofo
  systemctl start jitsi-videobridge2

  # 创建开机自启动脚本
  echo "创建开机自启动脚本..."
  cat >/etc/systemd/system/jitsi-autostart.service <<EOF
[Unit]
Description=Jitsi Meet Auto Start Service
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'systemctl start nginx prosody jicofo jitsi-videobridge2'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  # 启用开机自启动服务
  systemctl daemon-reload
  systemctl enable jitsi-autostart.service

  echo "开机自启动配置完成"
}

# 修改interface.js文件设置项
change_interface_js() {
  echo "正在移除 Jitsi 水印..."
  local interface_config_path="/usr/share/jitsi-meet/interface_config.js"

  if [ -f "$interface_config_path" ]; then
    # 备份原始文件
    cp "$interface_config_path" "${interface_config_path}.backup"

    # 使用sed替换SHOW_JITSI_WATERMARK的值
    sed -i 's/SHOW_JITSI_WATERMARK: true/SHOW_JITSI_WATERMARK: false/' "$interface_config_path"
    sed -i 's/DISABLE_JOIN_LEAVE_NOTIFICATIONS: false/DISABLE_JOIN_LEAVE_NOTIFICATIONS: true/' "$interface_config_path"
    if [ $? -eq 0 ]; then
      echo "成功设置interface.config"
    else
      echo "设置interface.config发生错误"
      # 如果修改失败，恢复备份
      cp "${interface_config_path}.backup" "$interface_config_path"
    fi
  else
    echo "警告: 未找到 interface_config.js 文件"
  fi
}

# 配置默认设置项
configure_default_setting() {
  if [ -f "./configure_jvb.sh" ]; then
    echo "正在配置 jvb..."
    bash ./configure_jvb.sh "$1"
  fi

  if [ -f "./configure_sip.sh" ]; then
    echo "正在配置 sip..."
    bash ./configure_sip.sh "$1"
  fi
}

# 检查 Ubuntu 版本并安装 prosody 相关依赖
check_and_install_prosody() {
  echo "检查 Ubuntu 版本..."
  # 获取 Ubuntu 版本号（例如：20.04）
  version=$(lsb_release -rs)

  # 将版本号转换为可比较的数字（例如：20.04 -> 2004）
  version_number=$(echo "$version" | sed 's/\.//')

  if [ $version_number -lt 2004 ]; then
    echo "Ubuntu 版本低于 20.04，使用旧版安装方式..."
    echo deb http://packages.prosody.im/debian $(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list
    wget https://prosody.im/files/prosody-debian-packages.key -O- | sudo apt-key add -
  else
    echo "Ubuntu 版本 20.04 或更高，使用新版安装方式..."
    sudo mkdir -p /etc/apt/keyrings
    sudo curl -sL https://prosody.im/files/prosody-debian-packages.key -o /etc/apt/keyrings/prosody-debian-packages.key
    echo "deb [signed-by=/etc/apt/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/prosody-debian-packages.list
  fi

  # 更新包列表并安装 lua5.2
  apt-get update -qq
  apt-get install -y lua5.2
}

# 主安装流程
main() {
  local IP_ADDRESS=""

  # 首先检查并卸载已存在的安装
  check_and_uninstall_jitsi

  # 检查版本并安装 prosody 相关依赖
  check_and_install_prosody

  # 如果提供了命令行参数,使用参数作为IP地址
  if [ $# -eq 1 ]; then
    if validate_ip "$1"; then
      IP_ADDRESS="$1"
    else
      echo "错误: 无效的IP地址格式"
      exit 1
    fi
  else
    # 如果没有提供参数,自动检测IP
    IP_ADDRESS=$(get_system_ip)
    echo "检测到系统IP地址: $IP_ADDRESS"
    read -p "是否使用此IP地址? [Y/n] " response
    response=${response:-Y}
    if [[ ! $response =~ ^[Yy]$ ]]; then
      read -p "请输入要使用的IP地址: " manual_ip
      if validate_ip "$manual_ip"; then
        IP_ADDRESS="$manual_ip"
      else
        echo "错误: 无效的IP地址格式"
        exit 1
      fi
    fi
  fi

  echo "开始安装 Jitsi Meet..."
  echo "将使用的IP地址: $IP_ADDRESS"

  # 更新包列表
  echo "正在更新软件包列表..."
  apt-get update -qq

  # 检查并安装必要的工具
  check_and_install_tools

  # 添加 Jitsi 仓库（如果尚未添加）
  if [ ! -f /etc/apt/sources.list.d/jitsi-stable.list ]; then
    echo "正在添加 Jitsi 仓库..."
    curl https://download.jitsi.org/jitsi-key.gpg.key | sudo sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'
    echo 'deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/' | sudo tee /etc/apt/sources.list.d/jitsi-stable.list >/dev/null
    apt-get -y update
  fi

  # 预配置 jitsi-videobridge 和 jitsi-meet-web-config
  echo "正在配置安装选项..."
  echo "jitsi-videobridge jitsi-videobridge/jvb-hostname string $IP_ADDRESS" | debconf-set-selections
  echo "jitsi-meet-web-config jitsi-meet/cert-choice select 'Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)'" | debconf-set-selections

  # 安装 Jitsi Meet
  echo "正在安装 Jitsi Meet..."
  DEBIAN_FRONTEND=noninteractive apt-get --option=Dpkg::Options::=--force-confold \
    --option=Dpkg::options::=--force-unsafe-io \
    --assume-yes --quiet install jitsi-meet

  # 检查防火墙设置
  check_firewall

  # 配置默认设置项
  configure_default_setting $IP_ADDRESS

  # 配置webview nginx
  configure_webview_nginx $IP_ADDRESS

  # 配置服务开机自启
  configure_autostart

  # 修改interface.js配置
  change_interface_js

  # 显示服务状态和开机自启状态
  echo "检查服务状态和开机自启配置："
  for service in nginx prosody jicofo jitsi-videobridge2; do
    printf "%-20s 运行状态: %s\t自启状态: %s\n" \
      "$service" \
      "$(systemctl is-active $service)" \
      "$(systemctl is-enabled $service)"
  done

  echo "安装完成!"

}

# 执行主函数
main "$@"
