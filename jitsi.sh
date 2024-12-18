#!/bin/bash

# 定义服务列表
SERVICES="jitsi-videobridge2 jicofo prosody nginx"

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 sudo 运行此脚本${NC}"
    exit 1
fi

# 检查服务状态的函数
check_status() {
    local all_running=true
    echo -e "\n${YELLOW}检查 Jitsi 服务状态：${NC}"
    for service in $SERVICES; do
        if systemctl is-active --quiet $service; then
            echo -e "${GREEN}$service 正在运行${NC}"
        else
            echo -e "${RED}$service 未运行${NC}"
            all_running=false
        fi
    done
    echo ""
    $all_running
}

# 启动服务的函数
start_jitsi() {
    echo -e "${YELLOW}正在启动 Jitsi 服务...${NC}"
    for service in $SERVICES; do
        echo "启动 $service..."
        systemctl start $service
    done
    check_status
}

# 停止服务的函数
stop_jitsi() {
    echo -e "${YELLOW}正在停止 Jitsi 服务...${NC}"
    for service in $SERVICES; do
        echo "停止 $service..."
        systemctl stop $service
    done
    check_status
}

# 重启服务的函数
restart_jitsi() {
    echo -e "${YELLOW}正在重启 Jitsi 服务...${NC}"
    for service in $SERVICES; do
        echo "重启 $service..."
        systemctl restart $service
    done
    check_status
}

# 重新安装函数
reinstall_jitsi() {
    local install_script="./install.sh"
    
    # 检查安装脚本是否存在
    if [ ! -f "$install_script" ]; then
        echo -e "${RED}错误：找不到安装脚本 (install.sh)${NC}"
        echo -e "${YELLOW}请确保安装脚本与当前脚本在同一目录下${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}准备重新安装 Jitsi...${NC}"
    echo -e "${YELLOW}开始执行重新安装...${NC}"
    bash "$install_script"
}

# 主菜单
show_menu() {
    echo -e "\n${GREEN}Jitsi 服务控制脚本${NC}"
    echo "------------------------"
    echo "1. 启动 Jitsi"
    echo "2. 停止 Jitsi"
    echo "3. 重启 Jitsi"
    echo "4. 查看状态"
    echo "5. 重新安装"
    echo "6. 退出"
    echo "------------------------"
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 (1-6): " choice
    case $choice in
        1)
            start_jitsi
            ;;
        2)
            stop_jitsi
            ;;
        3)
            restart_jitsi
            ;;
        4)
            check_status
            ;;
        5)
            reinstall_jitsi
            ;;  
        6)
            echo -e "${GREEN}感谢使用！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选择，请重试${NC}"
            ;;
    esac
done