#!/bin/bash
# 一键配置

generate_config_file() {
    if [[ -f /usr/bin/ljfxznode ]]; then
        /usr/bin/ljfxznode generate
    else
        echo -e "${red}未找到 ljfxznode 管理脚本，请先完成安装${plain}"
    fi
}
