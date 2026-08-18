#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(uname -m)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
else
    echo -e "${red}当前版本仅支持 Linux amd64 (x86_64)，检测到架构: ${arch}${plain}"
    exit 1
fi

echo "架构: ${arch}"

# os version
# 解析只取主版本号。原 -F'[= ."]' 在 gawk 下会把 VERSION_ID="24.04" 切成 VERSION_ID/24/04，
# $3 取到次版本 04，导致 Ubuntu 24.04 被误判为 < 16；统一改为按 = 分割后去引号再截主版本。
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F= '/^DISTRIB_RELEASE=/{gsub(/"/,"",$2); print $2; exit}' /etc/lsb-release)
fi
os_version=${os_version%%.*}

# 无法确定版本时跳过版本门槛检查
if [[ -n "$os_version" ]]; then
    if [[ x"${release}" == x"centos" ]]; then
        if [[ ${os_version} -le 6 ]]; then
            echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
        fi
    elif [[ x"${release}" == x"ubuntu" ]]; then
        if [[ ${os_version} -lt 16 ]]; then
            echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
        fi
    elif [[ x"${release}" == x"debian" ]]; then
        if [[ ${os_version} -lt 8 ]]; then
            echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
        fi
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y >/dev/null 2>&1
        update-ca-trust force-enable >/dev/null 2>&1
    elif [[ x"${release}" == x"alpine" ]]; then
        # 管理脚本与安装脚本均以 #!/bin/bash 运行，alpine 默认无 bash，必须一并安装
        apk add bash wget curl unzip tar socat ca-certificates >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"debian" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"ubuntu" ]]; then
        apt-get update -y >/dev/null 2>&1
        apt install wget curl unzip tar cron socat ca-certificates -y >/dev/null 2>&1
        update-ca-certificates >/dev/null 2>&1
    elif [[ x"${release}" == x"arch" ]]; then
        pacman -Sy --noconfirm >/dev/null 2>&1
        pacman -S --noconfirm --needed wget curl unzip tar cron socat ca-certificates >/dev/null 2>&1
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/ljfxznode/ljfxznode ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service ljfxznode status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status ljfxznode | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

install_ljfxznode() {
    mkdir /usr/local/ljfxznode/ -p
    cd /usr/local/ljfxznode/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/csdfsdffese/ljfxznode/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 ljfxznode 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 ljfxznode 版本安装${plain}"
            exit 1
        fi
        echo -e "检测到 ljfxznode 最新版本：${last_version}，开始安装"
        wget --no-check-certificate -N --progress=bar -O /usr/local/ljfxznode/ljfxznode-linux.zip https://github.com/csdfsdffese/ljfxznode/releases/download/${last_version}/ljfxznode-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            rm -f /usr/local/ljfxznode/ljfxznode-linux.zip
            echo -e "${red}下载 ljfxznode 失败，请确保你的服务器能够下载 Github 的文件，原程序未受影响${plain}"
            exit 1
        fi
    else
        last_version=$1
        if [[ "$last_version" != v* ]]; then
            last_version="v$last_version"
        fi
        url="https://github.com/csdfsdffese/ljfxznode/releases/download/${last_version}/ljfxznode-linux-${arch}.zip"
        echo -e "开始安装 ljfxznode $last_version"
        wget --no-check-certificate -N --progress=bar -O /usr/local/ljfxznode/ljfxznode-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            rm -f /usr/local/ljfxznode/ljfxznode-linux.zip
            echo -e "${red}下载 ljfxznode $last_version 失败，请确保此版本存在，原程序未受影响${plain}"
            exit 1
        fi
    fi

    # 下载成功后才动旧程序；先校验压缩包完整性（GitHub 404 时 wget 退出码仍为 0，可能解出垃圾文件）
    if ! unzip -t ljfxznode-linux.zip >/dev/null 2>&1; then
        rm -f ljfxznode-linux.zip
        echo -e "${red}下载的压缩包校验失败（可能是 404 页面或网络异常），原程序未受影响${plain}"
        exit 1
    fi
    # 备份旧二进制，解压异常时回滚
    rm -f ljfxznode.bak
    if [[ -f ljfxznode ]]; then
        mv ljfxznode ljfxznode.bak
    fi
    unzip -o ljfxznode-linux.zip
    rm ljfxznode-linux.zip -f
    # 校验全部必需产物（GitHub 404 时 wget 退出码可能为 0，zip 内可能缺文件）
    missing=""
    for f in ljfxznode geoip.dat geosite.dat config.json dns.json route.json custom_outbound.json custom_inbound.json; do
        if [[ ! -f "$f" || ! -s "$f" ]]; then
            missing="$missing $f"
        fi
    done
    if [[ -n "$missing" ]]; then
        if [[ -f ljfxznode.bak ]]; then
            mv -f ljfxznode.bak ljfxznode
        fi
        echo -e "${red}解压产物不完整，缺失:${missing} 已恢复原程序${plain}"
        exit 1
    fi
    rm -f ljfxznode.bak
    chmod +x ljfxznode
    mkdir /etc/ljfxznode/ -p
    cp geoip.dat /etc/ljfxznode/
    cp geosite.dat /etc/ljfxznode/
    if [[ x"${release}" == x"alpine" ]]; then
        rm /etc/init.d/ljfxznode -f
        cat <<EOF > /etc/init.d/ljfxznode
#!/sbin/openrc-run

name="ljfxznode"
description="ljfxznode"

command="/usr/local/ljfxznode/ljfxznode"
command_args="server"
command_user="root"

pidfile="/run/ljfxznode.pid"
command_background="yes"

depend() {
        need net
}
EOF
        chmod +x /etc/init.d/ljfxznode
        rc-update add ljfxznode default
        echo -e "${green}ljfxznode ${last_version}${plain} 安装完成，已设置开机自启"
    else
        rm /etc/systemd/system/ljfxznode.service -f
        cat <<EOF > /etc/systemd/system/ljfxznode.service
[Unit]
Description=ljfxznode Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/ljfxznode/
ExecStart=/usr/local/ljfxznode/ljfxznode server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl stop ljfxznode
        systemctl enable ljfxznode
        echo -e "${green}ljfxznode ${last_version}${plain} 安装完成，已设置开机自启"
    fi

    if [[ ! -f /etc/ljfxznode/config.json ]]; then
        cp config.json /etc/ljfxznode/
        echo -e ""
        echo -e "全新安装，请先参看教程：https://github.com/csdfsdffese/ljfxznode，配置必要的内容"
        first_install=true
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service ljfxznode start
        else
            systemctl start ljfxznode
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e ""
            echo -e "${green}ljfxznode 重启成功${plain}"
        else
            echo -e ""
            echo -e "${red}ljfxznode 可能启动失败，请稍后使用 ljfxznode log 查看日志信息，若无法启动，则可能更改了配置格式，请前往 wiki 查看：https://github.com/csdfsdffese/ljfxznode/wiki${plain}"
        fi
        first_install=false
    fi

    if [[ ! -f /etc/ljfxznode/dns.json ]]; then
        cp dns.json /etc/ljfxznode/
    fi
    if [[ ! -f /etc/ljfxznode/route.json ]]; then
        cp route.json /etc/ljfxznode/
    fi
    if [[ ! -f /etc/ljfxznode/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/ljfxznode/
    fi
    if [[ ! -f /etc/ljfxznode/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/ljfxznode/
    fi
    # 管理脚本先下载到临时文件校验后原子替换，失败时旧脚本不受影响
    tmp_file=$(mktemp)
    if curl -fsL -o "$tmp_file" https://raw.githubusercontent.com/csdfsdffese/ljfxznode-script/master/ljfxznode.sh && [[ -s "$tmp_file" ]]; then
        chmod +x "$tmp_file"
        mv -f "$tmp_file" /usr/bin/ljfxznode
        chmod +x /usr/bin/ljfxznode
    else
        rm -f "$tmp_file"
        echo -e "${red}下载管理脚本失败，原管理脚本未受影响，可稍后执行 ljfxznode update_shell 重新下载${plain}"
    fi
    cd $cur_dir
    # 注意：不自删本脚本（install.sh 实际是被 ljfxznode 下载到临时文件后 bash 执行的，
    # 删除 install.sh 是空操作，反而可能误删调用目录下的同名文件）
    echo -e ""
    echo "ljfxznode 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "ljfxznode              - 显示管理菜单 (功能更多)"
    echo "ljfxznode start        - 启动 ljfxznode"
    echo "ljfxznode stop         - 停止 ljfxznode"
    echo "ljfxznode restart      - 重启 ljfxznode"
    echo "ljfxznode status       - 查看 ljfxznode 状态"
    echo "ljfxznode enable       - 设置 ljfxznode 开机自启"
    echo "ljfxznode disable      - 取消 ljfxznode 开机自启"
    echo "ljfxznode log          - 查看 ljfxznode 日志"
    echo "ljfxznode x25519       - 生成 x25519 密钥"
    echo "ljfxznode generate     - 生成 ljfxznode 配置文件"
    echo "ljfxznode update       - 更新 ljfxznode"
    echo "ljfxznode update x.x.x - 更新 ljfxznode 指定版本"
    echo "ljfxznode install      - 安装 ljfxznode"
    echo "ljfxznode uninstall    - 卸载 ljfxznode"
    echo "ljfxznode version      - 查看 ljfxznode 版本"
    echo "------------------------------------------"
    # 首次安装询问是否生成配置文件
    if [[ $first_install == true ]]; then
        read -rp "检测到你为第一次安装ljfxznode,是否自动直接生成配置文件？(y/n): " if_generate
        if [[ $if_generate == [Yy] ]]; then
            tmp_file=$(mktemp)
            if curl -fsL -o "$tmp_file" https://raw.githubusercontent.com/csdfsdffese/ljfxznode-script/master/initconfig.sh && [[ -s "$tmp_file" ]]; then
                source "$tmp_file"
                rm -f "$tmp_file"
                generate_config_file
            else
                rm -f "$tmp_file"
                echo -e "${red}下载 initconfig.sh 失败，请稍后运行 ljfxznode generate 重新生成配置文件${plain}"
            fi
        fi
    fi
}

echo -e "${green}开始安装${plain}"
install_base
install_ljfxznode $1
