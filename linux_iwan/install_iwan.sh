#!/bin/bash

# 定义日志函数，方便记录操作信息
log() {
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1"
}

# 目标目录
TARGET_DIR="/etc/sdwan"

# 检查目标目录是否存在，不存在则创建
if [ ! -d "$TARGET_DIR" ]; then
    log "目标目录 $TARGET_DIR 不存在，开始创建..."
    mkdir -p "$TARGET_DIR"
    if [ $? -ne 0 ]; then
        log "创建目标目录 $TARGET_DIR 失败，退出脚本。"
        exit 1
    fi
    log "目标目录 $TARGET_DIR 创建成功。"
fi

# 检查执行目录下是否有 linux_sdwand_x86 文件
if [ -f "linux_sdwand_x86" ]; then
    log "发现 linux_sdwand_x86 文件，开始复制到 $TARGET_DIR..."
    cp "linux_sdwand_x86" "$TARGET_DIR/iwan_panabit.sh"
    if [ $? -ne 0 ]; then
        log "复制文件到 $TARGET_DIR/iwan_panabit.sh 失败，退出脚本。"
        exit 1
    fi
    log "文件已成功复制到 $TARGET_DIR/iwan_panabit.sh。"
else
    log "未找到 linux_sdwand_x86 文件，开始从 GitHub 下载..."
    wget -q -O "$TARGET_DIR/iwan_panabit.sh" \
        "https://github.com/oldfeecn/panabit_h/raw/refs/heads/main/linux_iwan/linux_sdwand_x86"
    if [ $? -ne 0 ]; then
        log "从 GitHub 下载文件到 $TARGET_DIR/iwan_panabit.sh 失败，退出脚本。"
        exit 1
    fi
    log "文件已成功从 GitHub 下载到 $TARGET_DIR/iwan_panabit.sh。"
fi

# 给 iwan_panabit.sh 文件赋予执行权限
log "开始给 $TARGET_DIR/iwan_panabit.sh 赋予执行权限..."
chmod +x "$TARGET_DIR/iwan_panabit.sh"
if [ $? -ne 0 ]; then
    log "给 $TARGET_DIR/iwan_panabit.sh 赋予执行权限失败，退出脚本。"
    exit 1
fi
log "$TARGET_DIR/iwan_panabit.sh 已被赋予执行权限。"

#!/bin/bash

# 定义目录和文件路径
CONFIG_DIR="/etc/sdwan"
CONFIG_PATTERN="${CONFIG_DIR}/iwan*.conf"
SERVICE_STARTUP_FILE="/etc/systemd/system/iwan.service"
SERVICE_STARTUP_CONTENT="[Unit]
Description=IWAN Service
After=network.target

[Service]
ExecStart=/etc/sdwan/install_iwan.sh
Restart=always

[Install]
WantedBy=multi-user.target"

# 添加到开机启动
add_to_startup() {
    if [ -f "$SERVICE_STARTUP_FILE" ]; then
        read -p "开机启动项已存在，是否覆盖？(y/n): " overwrite
        if [ "$overwrite" = "y" ] || [ "$overwrite" = "Y" ]; then
            echo "覆盖开机启动项..."
            echo "$SERVICE_STARTUP_CONTENT" | sudo tee "$SERVICE_STARTUP_FILE" > /dev/null
            sudo systemctl daemon-reload
            sudo systemctl enable iwan.service
            echo "开机启动项已覆盖。"
        else
            echo "取消覆盖开机启动项。"
        fi
    else
        echo "添加脚本到开机启动..."
        echo "$SERVICE_STARTUP_CONTENT" | sudo tee "$SERVICE_STARTUP_FILE" > /dev/null
        sudo systemctl daemon-reload
        sudo systemctl enable iwan.service
        echo "脚本已添加到开机启动。"
    fi
}

# 判断并添加路由
add_routes() {
    echo "Adding routes..."
    for config_file in $CONFIG_PATTERN; do
        server=$(grep 'server=' "$config_file" | cut -d'=' -f2)
        if ! ip route | grep -q "$server/32"; then
            # 获取默认网关
            gateway=$(ip route | grep default | awk '{print $3}')
            if [ -n "$gateway" ]; then
                ip route add "$server/32" via "$gateway"
                echo "Route added for $server via $gateway"
            else
                echo "No default gateway found. Route not added for $server"
            fi
        else
            echo "Route for $server already exists."
        fi
    done
}

# 删除之前添加的路由
delete_routes() {
    echo "Deleting routes..."
    for config_file in $CONFIG_PATTERN; do
        server=$(grep 'server=' "$config_file" | cut -d'=' -f2)
        if ip route | grep -q "$server/32"; then
            ip route del "$server/32"
            echo "Route deleted for $server"
        else
            echo "Route for $server does not exist."
        fi
    done
}

# 管理iwan接口及其配置文件
manage_interfaces() {
    echo "Managing iwan interfaces..."
    for config_file in $CONFIG_PATTERN; do
        interface_name=$(grep -oP '\[\K[^\]]+' "$config_file")
        server=$(grep 'server=' "$config_file" | cut -d'=' -f2)
        username=$(grep 'username=' "$config_file" | cut -d'=' -f2)
        password=$(grep 'password=' "$config_file" | cut -d'=' -f2)
        port=$(grep 'port=' "$config_file" | cut -d'=' -f2)
        mtu=$(grep 'mtu=' "$config_file" | cut -d'=' -f2)
        encrypt=$(grep 'encrypt=' "$config_file" | cut -d'=' -f2)
        pipeid=$(grep 'pipeid=' "$config_file" | cut -d'=' -f2)
        pipeidx=$(grep 'pipeidx=' "$config_file" | cut -d'=' -f2)

        # 示例：创建或更新接口配置
        echo "Configuring interface $interface_name..."
        # 这里可以添加具体的接口配置命令
    done
}

# 重启iwan服务
restart_iwan_service() {
    echo "Restarting iwan service..."
    delete_routes  # 先删除路由
    pids=$(pgrep -f "iwan_panabit.sh")
    if [ ! -z "$pids" ]; then
        echo "Killing existing iwan processes..."
        sudo kill $pids
    fi
    add_routes  # 重新添加路由
    /etc/sdwan/iwan_panabit.sh -f $CONFIG_PATTERN &
    echo "iwan service restarted."
}

# 显示菜单并执行相应操作
show_menu() {
    while true; do
        echo "请选择一个操作："
        echo "1. 添加到开机启动"
        echo "3. 管理iwan接口及其配置文件"
        echo "4. 重启iwan服务"
        echo "5. 退出"
        read -p "输入数字选择操作: " choice

        case $choice in
            1) add_to_startup ;;
            3) manage_interfaces ;;
            4) restart_iwan_service ;;
            5) echo "退出脚本"; exit 0 ;;
            *) echo "无效的选项，请重新输入。" ;;
        esac
    done
}

# 主逻辑
show_menu
