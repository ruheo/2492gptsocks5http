#!/bin/bash

# Socks5 和 Nginx 安装脚本

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo "请以root用户身份运行"
    exit 1
fi

# 获取脚本参数
AUTH_MODE=${1:-password}  # 认证模式：noauth（无认证）或 password（需要认证）
PORT=${2:-9999}
USER=${3:-caishen891}
PASSWD=${4:-999999}
NGINX_PORT=${5:-8080}

# 如果认证模式是 noauth，则忽略用户名和密码
if [ "$AUTH_MODE" = "noauth" ]; then
    USER=""
    PASSWD=""
fi

# 显示调试信息
echo "当前认证模式: $AUTH_MODE"
echo "SOCKS5 端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASSWD"
echo "Nginx 端口: $NGINX_PORT"

# 设置变量
SOCKS_BIN="/usr/local/bin/socks"
SERVICE_FILE="/etc/systemd/system/sockd.service"
CONFIG_FILE="/etc/socks/config.yaml"
PACKAGE_MANAGER=""
FIREWALL_COMMAND=""
NGINX_CONF="/etc/nginx/conf.d/proxy.conf"
PYTHON_CMD="python3"

# 确定包管理器和防火墙命令
if command -v yum &> /dev/null; then
    PACKAGE_MANAGER="yum"
    FIREWALL_COMMAND="firewall-cmd --add-port=$PORT/tcp --permanent && firewall-cmd --add-port=$NGINX_PORT/tcp --permanent && firewall-cmd --reload"
elif command -v apt-get &> /dev/null; then
    PACKAGE_MANAGER="apt-get"
    FIREWALL_COMMAND="ufw allow $PORT && ufw allow $NGINX_PORT"
else
    echo "不支持的系统，请手动安装所需的软件包并配置防火墙。"
    exit 1
fi

# 检查 Python 环境
if ! command -v $PYTHON_CMD &> /dev/null; then
    echo "未找到 Python3，正在安装..."
    $PACKAGE_MANAGER update -y
    $PACKAGE_MANAGER install -y python3
    if ! command -v $PYTHON_CMD &> /dev/null; then
        echo "Python3 安装失败，请手动安装 Python3 并重试。"
        exit 1
    fi
else
    echo "Python3 已经安装。"
fi

# 检查 Nginx 是否安装，如果没有安装则自动安装
if ! command -v nginx &> /dev/null; then
    echo "未找到 Nginx，正在安装..."
    if [ "$PACKAGE_MANAGER" = "yum" ]; then
        $PACKAGE_MANAGER install -y nginx
    elif [ "$PACKAGE_MANAGER" = "apt-get" ]; then
        $PACKAGE_MANAGER update -y
        $PACKAGE_MANAGER install -y nginx
    fi
else
    echo "Nginx 已经安装。"
fi

# 安装必要的软件包
for cmd in wget lsof; do
    command -v $cmd &> /dev/null || {
        echo "$cmd 未安装，正在安装..."
        $PACKAGE_MANAGER install -y $cmd
    }
done


# 下载并设置Socks5二进制文件
if [ ! -f "$SOCKS_BIN" ]; then
    echo "下载 Socks5 二进制文件..."
    wget -O "$SOCKS_BIN" --no-check-certificate https://github.com/ruheo/socks5/raw/main/socks || {
        echo "下载 Socks5 二进制文件失败"
        exit 1
    }
    chmod +x "$SOCKS_BIN"
else
    echo "Socks5 二进制文件已经存在，跳过下载。"
fi

# 创建Socks5 systemd服务文件
if [ ! -f "$SERVICE_FILE" ]; then
    echo "创建 Socks5 服务文件..."
    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Socks Service
After=network.target nss-lookup.target

[Service]
User=socksuser
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$SOCKS_BIN run -config $CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
else
    echo "Socks5 服务文件已经存在，跳过创建。"
fi

# 调用 Python 脚本生成配置文件
$PYTHON_CMD << EOF
import json
import os

auth_mode = "$AUTH_MODE"
port = "$PORT"
user = "$USER"
passwd = "$PASSWD"
config_file = "$CONFIG_FILE"

config = {
    "log": {"loglevel": "warning"},
    "routing": {"domainStrategy": "AsIs"},
    "inbounds": [{
        "listen": "0.0.0.0",
        "port": port,
        "protocol": "socks",
        "settings": {
            "auth": auth_mode,
            "udp": True
        },
        "streamSettings": {"network": "tcp"}
    }],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"}
    ]
}

if auth_mode == "password":
    config["inbounds"][0]["settings"]["accounts"] = [{"user": user, "pass": passwd}]

os.makedirs(os.path.dirname(config_file), exist_ok=True)
with open(config_file, "w") as f:
    json.dump(config, f, indent=4)

EOF

# 创建专用用户
if ! id "socksuser" &>/dev/null; then
    echo "创建用户 socksuser..."
    useradd -r -s /sbin/nologin socksuser
else
    echo "用户 socksuser 已经存在"
fi

# 配置 Nginx
if [ ! -f "$NGINX_CONF" ]; then
    echo "配置 Nginx 以支持 HTTP 代理..."
    cat <<EOF > "$NGINX_CONF"
server {
    listen $NGINX_PORT;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
else
    echo "Nginx 配置文件已经存在，跳过配置。"
fi

# 启用并启动Socks5服务
echo "启用并启动 Socks5 服务..."
systemctl daemon-reload
systemctl enable sockd.service
systemctl start sockd.service

# 启动 Nginx 服务
echo "启动 Nginx 服务..."
systemctl restart nginx

# 配置防火墙
echo "配置防火墙..."
eval "$FIREWALL_COMMAND"

# 显示连接信息
IPv4=$(curl -4 ip.sb)
IPv6=$(curl -6 ip.sb 2>/dev/null)  # 忽略IPv6连接错误
HTTP_PROXY_URL="http://$USER:$PASSWD@$(hostname -I | awk '{print $1}'):${NGINX_PORT}"
echo -e "IPv4: $IPv4\nIPv6: $IPv6\nSOCKS5 端口: $PORT"
if [ "$AUTH_MODE" = "password" ]; then
    echo -e "SOCKS5 认证用户名: $USER\nSOCKS5 认证密码: $PASSWD"
else
    echo -e "SOCKS5 代理使用无认证模式（noauth）"
fi
echo -e "HTTP 代理地址: $HTTP_PROXY_URL"

# 生成卸载脚本
cat <<EOF > /usr/local/bin/uninstall_socks.sh
#!/bin/bash

# 停止服务
systemctl stop sockd.service
systemctl stop nginx

# 禁用服务
systemctl disable sockd.service
systemctl disable nginx

# 删除systemd服务文件
rm /etc/systemd/system/sockd.service

# 删除Socks5二进制文件
rm /usr/local/bin/socks

# 删除配置文件和目录
rm -rf /etc/socks

# 删除Nginx配置文件
rm /etc/nginx/conf.d/proxy.conf

# 删除用户
if id "socksuser" &>/dev/null; then
    userdel -r socksuser
fi

# 重新加载systemd守护进程
systemctl daemon-reload

# 关闭防火墙端口（适用于CentOS/RedHat使用firewalld的情况）
if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --remove-port=$PORT/tcp --permanent
    firewall-cmd --remove-port=$NGINX_PORT/tcp --permanent
    firewall-cmd --reload
fi

# 关闭防火墙端口（适用于Ubuntu/Debian使用ufw的情况）
if command -v ufw &> /dev/null; then
    ufw delete allow $PORT
    ufw delete allow $NGINX_PORT
fi

echo "Socks5代理和Nginx服务已停止并卸载"
EOF

# 设置卸载脚本的可执行权限
chmod +x /usr/local/bin/uninstall_socks.sh

# 提示用户卸载命令
echo "Socks5代理和Nginx安装成功！如需卸载，请执行以下命令："
echo "bash /usr/local/bin/uninstall_socks.sh"
