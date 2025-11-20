#!/bin/sh

set -x 

# 配置路径和端口
ZT_PORT=9993
ZEROTIER_PATH="/var/lib/zerotier-one"

PUB_FILE="identity.public"
SEC_FILE="identity.secret"
MOON_FILE="moon.json"

# 初始化 ZeroTier 数据
function init_zerotier() {
    cd $ZEROTIER_PATH

    # 生成ZeroTier API访问密钥
    openssl rand -hex 16 > authtoken.secret

    # 生成身份凭证
    zerotier-idtool generate ${SEC_FILE} ${PUB_FILE}
    
    # 根据身份凭证生成moon.json文件
    zerotier-idtool initmoon identity.public > ${MOON_FILE}
}

validate_zt_files_silent() {

    local -r SILENT=" > /dev/null 2>&1"

    # --- 1. Validate identity.public format ---
    # Check file existence first
    [ -f "$PUB_FILE" ] || return 1 
    # Check validation command
    eval "zerotier-idtool validate $PUB_FILE $SILENT" || return 2

    # --- 2. Validate identity.secret format ---
    [ -f "$SEC_FILE" ] || return 3
    eval "zerotier-idtool validate $SEC_FILE $SILENT" || return 4

    # --- 3. Check Public/Secret Key Association ---
    PUBLIC_ID=$(awk 'NR==1 {print $NF}' "$PUB_FILE")
    # Capture validation output silently to extract ID
    SECRET_ID=$(zerotier-idtool validate "$SEC_FILE" 2>/dev/null | awk '/validated successfully/ {print $NF}')
    
    # Check if IDs match and are not empty
    if [ "$PUBLIC_ID" != "$SECRET_ID" ] || [ -z "$PUBLIC_ID" ]; then
        return 5 # Public/Secret mismatch or ID empty
    fi

    # --- 4. Validate moon.json structure ---
    if [ -f "$MOON_FILE" ]; then
        # Attempt to generate moon file
        if eval "zerotier-idtool genmoon $MOON_FILE $SILENT"; then
            # Clean up the generated temporary .moon file silently
            rm -f 000000*.moon > /dev/null 2>&1
        else
            return 6 # moon.json structure failed
        fi
    fi
    
    # All checks passed
    return 0
}

# 检查并初始化 ZeroTier
function check_zerotier() {
    if [ ! -d "$ZEROTIER_PATH" ]; then
        if mkdir -p "$ZEROTIER_PATH"; then
            echo "Error: Failed to create directory $ZEROTIER_PATH." >&2
            return 1 # 创建目录失败，直接返回
        fi
    fi

    if [ "$(ls -A $ZEROTIER_PATH)" ]; then
        validate_zt_files_silent
        if [ $? -eq 0 ];then 
            return
        fi
    else
        init_zerotier
    fi
}

# 启动 ZeroTier 
function main() {
    check_zerotier

    # 将back下的内容移动到ZEROTIER_HOME下
    cp -ar ${ZEROTIER_HOME} ${BACK_PATH}

    cd $ZEROTIER_PATH && zerotier-one -p${ZT_PORT} || exit 1
}

main