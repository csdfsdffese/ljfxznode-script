#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启ljfxznode" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    tmp_file=$(mktemp)
    if ! curl -fsL -o "$tmp_file" https://raw.githubusercontent.com/csdfsdffese/ljfxznode-script/master/install.sh; then
        echo -e "${red}拉取安装脚本失败，请检查本机能否连接 Github，原程序未受影响${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    if [[ ! -s "$tmp_file" ]]; then
        echo -e "${red}拉取到的安装脚本为空，原程序未受影响${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    bash "$tmp_file"
    ret=$?
    rm -f "$tmp_file"
    if [[ $ret != 0 ]]; then
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    if [[ $# == 0 ]]; then
        start
    else
        start 0
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    if [[ -n "$version" && "$version" != v* ]]; then
        version="v$version"
    fi
    tmp_file=$(mktemp)
    if ! curl -fsL -o "$tmp_file" https://raw.githubusercontent.com/csdfsdffese/ljfxznode-script/master/install.sh; then
        echo -e "${red}拉取安装脚本失败，请检查本机能否连接 Github，原程序未受影响${plain}"
        rm -f "$tmp_file"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    if [[ ! -s "$tmp_file" ]]; then
        echo -e "${red}拉取到的安装脚本为空，原程序未受影响${plain}"
        rm -f "$tmp_file"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi
    bash "$tmp_file" $version
    ret=$?
    rm -f "$tmp_file"
    if [[ $ret == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 ljfxznode，请使用 ljfxznode log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "ljfxznode在修改配置后会自动尝试重启"
    vi /etc/ljfxznode/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "ljfxznode状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动ljfxznode或ljfxznode自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "ljfxznode状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 ljfxznode 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service ljfxznode stop
        rc-update del ljfxznode
        rm /etc/init.d/ljfxznode -f
    else
        systemctl stop ljfxznode
        systemctl disable ljfxznode
        rm /etc/systemd/system/ljfxznode.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/ljfxznode/ -rf
    rm /usr/local/ljfxznode/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/ljfxznode -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}ljfxznode已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service ljfxznode start
        else
            systemctl start ljfxznode
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}ljfxznode 启动成功，请使用 ljfxznode log 查看运行日志${plain}"
        else
            echo -e "${red}ljfxznode可能启动失败，请稍后使用 ljfxznode log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service ljfxznode stop
    else
        systemctl stop ljfxznode
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}ljfxznode 停止成功${plain}"
    else
        echo -e "${red}ljfxznode停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service ljfxznode restart
    else
        systemctl restart ljfxznode
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}ljfxznode 重启成功，请使用 ljfxznode log 查看运行日志${plain}"
    else
        echo -e "${red}ljfxznode可能启动失败，请稍后使用 ljfxznode log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service ljfxznode status
    else
        systemctl status ljfxznode --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add ljfxznode
    else
        systemctl enable ljfxznode
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}ljfxznode 设置开机自启成功${plain}"
    else
        echo -e "${red}ljfxznode 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del ljfxznode
    else
        systemctl disable ljfxznode
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}ljfxznode 取消开机自启成功${plain}"
    else
        echo -e "${red}ljfxznode 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u ljfxznode.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    tmp_file=$(mktemp)
    if ! curl -fL -o "$tmp_file" https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh; then
        echo -e "${red}拉取 BBR 脚本失败，请检查本机能否连接 Github${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    if [[ ! -s "$tmp_file" ]]; then
        echo -e "${red}拉取到的 BBR 脚本为空${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    bash "$tmp_file"
    rm -f "$tmp_file"
}

update_shell() {
    tmp_file=$(mktemp)
    if ! wget -O "$tmp_file" -N --no-check-certificate https://raw.githubusercontent.com/csdfsdffese/ljfxznode-script/master/ljfxznode.sh; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    if [[ ! -s "$tmp_file" ]]; then
        echo ""
        echo -e "${red}下载到的脚本为空，请检查本机能否连接 Github${plain}"
        rm -f "$tmp_file"
        before_show_menu
        return 1
    fi
    chmod +x "$tmp_file"
    mv -f "$tmp_file" /usr/bin/ljfxznode
    echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
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

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep ljfxznode)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled ljfxznode)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}ljfxznode已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装ljfxznode${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "ljfxznode状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "ljfxznode状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "ljfxznode状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/ljfxznode/ljfxznode x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_ljfxznode_version() {
    echo -n "ljfxznode 版本："
    /usr/local/ljfxznode/ljfxznode version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    core="xray"
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    echo -e "${yellow}请选择节点传输协议：${plain}"
    echo -e "${green}1. Shadowsocks${plain}"
    echo -e "${green}2. Vless${plain}"
    echo -e "${green}3. Vmess${plain}"
    echo -e "${green}4. Trojan${plain}"
    read -rp "请输入：" NodeType
    case "$NodeType" in
        1 ) NodeType="shadowsocks" ;;
        2 ) NodeType="vless" ;;
        3 ) NodeType="vmess" ;;
        4 ) NodeType="trojan" ;;
        * ) NodeType="shadowsocks" ;;
    esac
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com)：" certdomain
        if [ "$certmode" != "http" ]; then
            echo -e "${red}请手动修改配置文件后重启ljfxznode！${plain}"
        fi
    fi
    read -rp "是否启用TCP Fast Open(TFO)？(y/n，默认y)：" enable_tfo
    if [[ "$enable_tfo" =~ ^[Nn] ]]; then
        enable_tfo_value=false
    else
        enable_tfo_value=true
    fi
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 0,
            "ReportMinTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableTFO": $enable_tfo_value,
            "EnableDNS": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/ljfxznode/fullchain.cer",
                "KeyFile": "/etc/ljfxznode/cert.key",
                "Email": "ljfxznode@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        },
EOF
)
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}ljfxznode 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/ljfxznode/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/ljfxznode/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    nodes_config=()
    first_node=true
    fixed_api_info=false

    while true; do
        if [ "$first_node" = true ]; then
            read -rp "请输入机场网址(https://example.com)：" ApiHost
            read -rp "请输入面板对接API Key：" ApiKey
            read -rp "是否设置固定的机场网址和API Key？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}成功固定地址${plain}"
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(回车继续，输入n或no退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read -rp "请输入机场网址：" ApiHost
                read -rp "请输入面板对接API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    cores_config="[
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/ljfxznode/error.log\"
        },
        \"DnsConfigPath\": \"/etc/ljfxznode/dns.json\",
        \"RouteConfigPath\": \"/etc/ljfxznode/route.json\",
        \"InboundConfigPath\": \"/etc/ljfxznode/custom_inbound.json\",
        \"OutboundConfigPath\": \"/etc/ljfxznode/custom_outbound.json\"
    }]"

    # 切换到配置文件目录
    cd /etc/ljfxznode
    
    # 备份旧的配置文件（首次生成时不存在则不备份）
    [[ -f config.json ]] && mv config.json config.json.bak
    nodes_config_str="${nodes_config[*]}"
    formatted_nodes_config="${nodes_config_str%,}"

    # 创建 config.json 文件
    cat <<EOF > /etc/ljfxznode/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [$formatted_nodes_config]
}
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/ljfxznode/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/ljfxznode/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    # 创建 dns.json 文件
    cat <<EOF > /etc/ljfxznode/dns.json
{
    "servers": [
        "1.1.1.1",
        "localhost"
    ],
    "tag": "dns_inbound"
}
EOF

    echo -e "${green}ljfxznode 配置文件生成完成，正在重新启动 ljfxznode 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
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
    echo "ljfxznode update x.x.x - 安装 ljfxznode 指定版本"
    echo "ljfxznode install      - 安装 ljfxznode"
    echo "ljfxznode uninstall    - 卸载 ljfxznode"
    echo "ljfxznode version      - 查看 ljfxznode 版本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}ljfxznode 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/csdfsdffese/ljfxznode ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 ljfxznode
  ${green}2.${plain} 更新 ljfxznode
  ${green}3.${plain} 卸载 ljfxznode
————————————————
  ${green}4.${plain} 启动 ljfxznode
  ${green}5.${plain} 停止 ljfxznode
  ${green}6.${plain} 重启 ljfxznode
  ${green}7.${plain} 查看 ljfxznode 状态
  ${green}8.${plain} 查看 ljfxznode 日志
————————————————
  ${green}9.${plain} 设置 ljfxznode 开机自启
  ${green}10.${plain} 取消 ljfxznode 开机自启
————————————————
  ${green}11.${plain} 一键安装 bbr (最新内核)
  ${green}12.${plain} 查看 ljfxznode 版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级 ljfxznode 维护脚本
  ${green}15.${plain} 生成 ljfxznode 配置文件
  ${green}16.${plain} 放行 VPS 的所有网络端口
  ${green}17.${plain} 退出脚本
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-17]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_ljfxznode_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) exit ;;
        *) echo -e "${red}请输入正确的数字 [0-17]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_ljfxznode_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
