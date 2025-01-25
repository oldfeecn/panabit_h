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
if [ -f "/etc/sdwan/linux_sdwand_x86" ]; then
    log "发现 linux_sdwand_x86 文件，开始复制到 $TARGET_DIR..."
    rm -rf "$TARGET_DIR/iwan_panabit.sh"
    cp "/etc/sdwan/linux_sdwand_x86" "$TARGET_DIR/iwan_panabit.sh"
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



# 定义目录和文件路径
CONFIG_DIR="/etc/sdwan"
CONFIG_PATTERN="${CONFIG_DIR}/iwan*.conf"
SERVICE_STARTUP_FILE="/etc/systemd/system/iwan.service"
SERVICE_STARTUP_CONTENT="[Unit]
Description=IWAN Service
After=network.target

[Service]
ExecStart=/etc/sdwan/install_iwan.sh restart_iwan_service
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
            # 获取默认网关，排除 iwan* 和 lo 接口
            gateway=$(ip route | grep default | grep -v 'iwan\|lo' | awk '{print $3}')
            if [ -n "$gateway" ]; then
                ip route add "$server/32" via "$gateway" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "Route added for $server via $gateway"
                else
                    echo "Failed to add route for $server via $gateway"
                fi
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



# 其他函数保持不变...


# 添加新接口
add_interface() {
    local interface_name="iwan"
    local index=1
    while [ -f "${CONFIG_DIR}/${interface_name}${index}.conf" ]; do
        ((index++))
    done
    interface_name="${interface_name}${index}"

    # 提示用户输入配置信息
    while true; do
        read -p "请输入对端IP: " server
        if ! echo "$server" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "无效的IP地址，请重新输入。"
        else
            break
        fi
    done

    read -p "请输入登录账号名: " username
    read -p "请输入密码: " password

    while true; do
        read -p "请输入对端端口: " port
        if ! echo "$port" | grep -qE '^[0-9]+$'; then
            echo "无效的端口号，请重新输入。"
        else
            break
        fi
    done

    read -p "请输入最大传输单元(MTU) (留空以保持不变): " mtu
    mtu=${mtu:-1436}  # 如果用户没有输入，则使用默认值 1436
    read -p "是否加密(0为不加密，1为加密，留空为不加密，默认0): " encrypt
    encrypt=${encrypt:-0}  # 如果用户没有输入，则使用默认值 0
    read -p "请输入管道ID(0为不带管道，管道取值1-1024，留空为不带管道，默认12): " pipeid
    pipeid=${pipeid:-12}  # 如果用户没有输入，则使用默认值 12
    read -p "请输入管道方向(管道一端为0，另一端为1，留空为不带管道，默认0): " pipeidx
    pipeidx=${pipeidx:-0}  # 如果用户没有输入，则使用默认值 0

    # 创建配置文件
    local config_file="${CONFIG_DIR}/${interface_name}.conf"
    cat > "$config_file" << EOF
    [$interface_name]
    server=$server
    username=$username
    password=$password
    port=$port
    mtu=$mtu
    encrypt=$encrypt
    pipeid=$pipeid
    pipeidx=$pipeidx
EOF

    echo "配置文件已生成: $config_file"

    # 添加路由
    add_routes

    # 重启IWAN服务
    restart_iwan_service
}

# 修改现有接口
modify_interface() {
    local config_files=($CONFIG_PATTERN)
    local num_configs=${#config_files[@]}

    if [ $num_configs -eq 0 ]; then
        echo "No iwan*.conf files found in $CONFIG_DIR."
        return
    fi

    # 列出所有接口供用户选择
    echo "Select an interface to modify:"
    for i in "${!config_files[@]}"; do
        echo "$((i+1))) ${config_files[$i]}"
    done

    # 提示用户选择要修改的接口
    read -p "Enter the number of the interface to modify (or 'q' to quit): " choice
    if [[ "$choice" =~ ^[qQ]$ ]]; then
        return
    fi

    # 验证用户输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$num_configs" ]; then
        echo "Invalid choice."
        return
    fi

    # 获取选定的配置文件
    local config_file="${config_files[$((choice-1))]}"
    local interface_name=$(grep -oP '\[\K[^\]]+' "$config_file")

    # 显示当前配置
    echo "Current configuration for $interface_name:"
    cat "$config_file"

    # 提示用户输入新的配置信息
    while true; do
        read -p "请输入对端IP (留空以保持不变): " server
        if [ -z "$server" ]; then
            server=$(grep 'server=' "$config_file" | cut -d'=' -f2)
            break
        elif ! echo "$server" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
            echo "无效的IP地址，请重新输入。"
        else
            break
        fi
    done

    read -p "请输入登录账号名 (留空以保持不变): " username
    read -p "请输入密码 (留空以保持不变): " password

    while true; do
        read -p "请输入对端端口 (留空以保持不变): " port
        if [ -z "$port" ]; then
            port=$(grep 'port=' "$config_file" | cut -d'=' -f2)
            break
        elif ! echo "$port" | grep -qE '^[0-9]+$'; then
            echo "无效的端口号，请重新输入。"
        else
            break
        fi
    done

    read -p "请输入最大传输单元(MTU) (留空以保持不变): " mtu
    read -p "是否加密(0为不加密，1为加密，留空以保持不变): " encrypt
    read -p "请输入管道ID(0为不带管道，管道取值1-1024，留空为不带管道): " pipeid
    read -p "请输入管道方向(管道一端为0，另一端为1，留空为不带管道): " pipeidx

    # 更新配置文件
    if [ -n "$server" ]; then
        sed -i "s/^server=.*/server=$server/" "$config_file"
    fi
    if [ -n "$username" ]; then
        sed -i "s/^username=.*/username=$username/" "$config_file"
    fi
    if [ -n "$password" ]; then
        sed -i "s/^password=.*/password=$password/" "$config_file"
    fi
    if [ -n "$port" ]; then
        sed -i "s/^port=.*/port=$port/" "$config_file"
    fi
    if [ -n "$mtu" ]; then
        sed -i "s/^mtu=.*/mtu=$mtu/" "$config_file"
    fi
    if [ -n "$encrypt" ]; then
        if grep -q "^encrypt=" "$config_file"; then
            sed -i "s/^encrypt=.*/encrypt=$encrypt/" "$config_file"
        else
            echo "encrypt=$encrypt" >> "$config_file"
        fi
    fi
    if [ -n "$pipeid" ]; then
        if grep -q "^pipeid=" "$config_file"; then
            sed -i "s/^pipeid=.*/pipeid=$pipeid/" "$config_file"
        else
            echo "pipeid=$pipeid" >> "$config_file"
        fi
    fi
    if [ -n "$pipeidx" ]; then
        if grep -q "^pipeidx=" "$config_file"; then
            sed -i "s/^pipeidx=.*/pipeidx=$pipeidx/" "$config_file"
        else
            echo "pipeidx=$pipeidx" >> "$config_file"
        fi
    fi

    echo "配置文件已更新: $config_file"

    # 添加路由
    add_routes

    # 重启IWAN服务
    restart_iwan_service
}


# 删除现有接口
delete_interface() {
    local config_files=($CONFIG_PATTERN)
    local num_configs=${#config_files[@]}

    if [ $num_configs -eq 0 ]; then
        echo "No iwan*.conf files found in $CONFIG_DIR."
        return
    fi

    # 列出所有接口供用户选择
    echo "Select an interface to delete:"
    for i in "${!config_files[@]}"; do
        echo "$((i+1))) ${config_files[$i]}"
    done

    # 提示用户选择要删除的接口
    read -p "Enter the number of the interface to delete (or 'q' to quit): " choice
    if [[ "$choice" =~ ^[qQ]$ ]]; then
        return
    fi

    # 验证用户输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$num_configs" ]; then
        echo "Invalid choice."
        return
    fi

    # 获取选定的配置文件
    local config_file="${config_files[$((choice-1))]}"

    # 关闭IWAN服务
    pids=$(pgrep -f "iwan_panabit.sh")
    if [ ! -z "$pids" ]; then
        echo "Killing existing iwan processes..."
        sudo kill $pids
    fi

    # 删除路由
    delete_routes

    # 删除配置文件
    rm "$config_file"
    if [ $? -eq 0 ]; then
        echo "配置文件已删除: $config_file"
    else
        echo "删除配置文件失败: $config_file"
    fi

    # 检查是否还有其他配置项
    config_files=($CONFIG_PATTERN)
    if [ ${#config_files[@]} -gt 0 ]; then
        # 如果还有其他配置项，则启动IWAN服务
        restart_iwan_service
    fi
}


# 重启iwan服务
restart_iwan_service() {
    echo "Restarting iwan service..."
    local config_files=($CONFIG_PATTERN)
    local num_configs=${#config_files[@]}

    if [ $num_configs -eq 0 ]; then
        echo "No iwan*.conf files found. Skipping service restart."
        return
    fi

    delete_routes  # 先删除路由

    pids=$(pgrep -f "iwan_panabit.sh")
    if [ ! -z "$pids" ]; then
        echo "Killing existing iwan processes..."
        sudo kill $pids
    fi
    add_routes #再添加路由

    # 遍历所有配置文件并启动IWAN服务
    for config_file in $CONFIG_PATTERN; do
        /etc/sdwan/iwan_panabit.sh -f "$config_file" &
         sleep 5  # 延时5秒，可以根据实际情况调整
    done

    echo "iwan service restarted."

    # 添加延时
    echo "Waiting for interfaces to initialize..."
    

    # 打印所有接口的IP地址信息
    echo "Printing IP addresses of all interfaces..."
    for config_file in $CONFIG_PATTERN; do
        interface_name=$(grep -oP '\[\K[^\]]+' "$config_file")
        if ip link show "$interface_name" > /dev/null 2>&1; then
            ip_address=$(ip addr show "$interface_name" | grep -oP 'inet \K[\d.]+')
            if [ -n "$ip_address" ]; then
                echo "Interface $interface_name has IP address $ip_address"
            else
                echo "Interface $interface_name does not have an IP address."
            fi
        else
            echo "Device \"$interface_name\" does not exist."
        fi
    done
    exit 0 ;
}



# 管理iwan接口及其配置文件
manage_interfaces() {
    echo "Managing iwan interfaces..."
    local config_files=($CONFIG_PATTERN)
    local num_configs=${#config_files[@]}

    if [ $num_configs -eq 0 ]; then
        echo "No iwan*.conf files found in $CONFIG_DIR."
    else
        echo "Found the following iwan*.conf files:"
        for config_file in "${config_files[@]}"; do
            echo "File: $config_file"
            cat "$config_file"
            echo
        done
    fi

    # 用户操作菜单
    while true; do
        echo "请选择一个操作："
        echo "1. 添加新接口"
        echo "2. 修改现有接口"
        echo "3. 删除现有接口"
        echo "4. 返回主菜单"
        read -p "输入数字选择操作: " choice

        case $choice in
            1) add_interface ;;
            2) modify_interface ;;
            3) delete_interface ;;
            4) break ;;
            *) echo "无效的选项，请重新输入。" ;;
        esac
    done
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


# 新增命令行参数处理逻辑
if [ "$1" == "restart" ]; then
    restart_iwan_service
    exit 0
else
    echo "未知命令: $1。请使用 'restart' 或其他支持的命令。"
    show_menu
fi


