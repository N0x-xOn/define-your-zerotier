#!/bin/bash

source "./build/build.sh"

# Build Feature Var
IMAGE_NAME="define-your-zerotier"
IMAGE_RP_USER="xoneki"
ZTN_RP="ZeroTierOne"
ZTN_RP_USER="zerotier"
RELEASES=""

# IP_ADDR*
PUBLIC_IPv4_CHECK_URL="https://ipv4.icanhazip.com/"
PUBLIC_IPv6_CHECK_URL="https://ipv6.icanhazip.com/"

IP_ADDR4=""
IP_ADDR6=""
KEY=""
MOON_NAME=""
ZTNCUI_PORT="3443"
FILE_SERVER_PORT="3000"

# ------------
# Utils Functions
# ------------

# 通过ZeroTier提供的版本信息配置构建版本tag
_getReleaseVersion() {
    local zerotier_release=$( curl -s https://download.zerotier.com/RELEASES/ | \
        grep -E 'href="[0-9]+\.[0-9]+\.[0-9]+/"' | \
        awk '{
            # 提取日期和时间（第3列和第4列）
            split($3, d, "-");
            month_map["Jan"]="01"; month_map["Feb"]="02"; month_map["Mar"]="03";
            month_map["Apr"]="04"; month_map["May"]="05"; month_map["Jun"]="06";
            month_map["Jul"]="07"; month_map["Aug"]="08"; month_map["Sep"]="09";
            month_map["Oct"]="10"; month_map["Nov"]="11"; month_map["Dec"]="12";
            # 生成可排序的时间戳（YYYYMMDDHHMM）
            key = d[3] month_map[d[2]] d[1] $4;
            gsub(/:/, "", key);  # 移除时间中的冒号（如 19:23 → 1923）
            print key " " $0;
        }' | \
        sort -k1n | \
        cut -d' ' -f2- | \
        tail -n 1 | \
        sed -n 's/.*href="\([0-9]\+\.[0-9]\+\.[0-9]\+\)\/".*/\1/p')
    
    if [ -z ${zerotier_release} ]; then
        return 1
    else
        RELEASES=${zerotier_release}
        return 0
    fi
}

_init_env_file() {
    sed -e "s#__IP_ADDR4__#${IP_ADDR4}#" \
    -e "s#__IP_ADDR6__#${IP_ADDR6}#" \
    -e "s#__API_PORT__#${API_PORT}#" \
    -e "s#__FILE_SERVER_PORT__#${FILE_SERVER_PORT}#" \
    -e "s#__DATA_PATH__#${DATA_PATH}#" \
    .env.template > .env
}

_get_ip() {
    IP_ADDR4=$(curl -s ${PUBLIC_IPv4_CHECK_URL})
    IP_ADDR6=$(curl -s ${PUBLIC_IPv6_CHECK_URL})
}


# Check docker image
# $1 check target image name 
# $2 image tag
check_image() {
    local image_name=$([ -n "$1" ] && echo "$1" || return 1)
    local image_tag=$([ -n "$2" ] && echo "$2" || return 1)

    docker images --format '{{json .Repository}}:{{json .Tag}}' | grep '"{$image_name}":"${image_tag}"' 2>&1 > /dev/null || return 1

    return 0
}

# $1 des port
check_port() {
    local port=$1
    if ss -tnlp | grep $port 2>&1 > /dev/null; then echo "端口${port}已被占用"; exit 1;fi
}

print_url() {
    echo "请访问 http://${IP_ADDR4}:${API_PORT} 进行配置"
    echo "默认用户名：admin"
    echo "默认密码：password"
    echo "请及时修改密码"
    echo "---------------------------"
    echo "moon配置和planet配置在 ${DATA_PATH} 目录下"
    echo "moons 文件下载： http://${IP_ADDR4}:${FILE_SERVER_PORT}/${MOON_NAME}?key=${KEY} "
    echo "planet文件下载： http://${IP_ADDR4}:${FILE_SERVER_PORT}/planet?key=${KEY} "
    echo "---------------------------"
    echo "请放行以下端口：${ZT_PORT}/tcp,${ZT_PORT}/udp，${API_PORT}/tcp，${FILE_SERVER_PORT}/tcp"
}


# ------------
# Pkg Functions
# ------------

extract_config() {
    _extract() {
        local config_name=$1
        cat ${DATA_PATH}/${config_name} | tr -d '\r'
    }
    IP_ADDR4=$(_extract "ip_addr4")
    IP_ADDR6=$(_extract "ip_addr6")
    KEY=$(_extract "file_server.key")
    MOON_NAME=$(ls ${DATA_PATH}/dist | grep moon | tr -d '\r')
}

extract_env() {
    local key_file="${PWD}/.env"
    if [ -f "${key_file}" ]; then
        IP_ADDR4=$(cat ${key_file} | grep "${IP_ADDR4}" | awk -F= '{print $2}')
        IP_ADDR4=$(cat ${key_file} | grep "${IP_ADDR4}" | awk -F= '{print $2}')
        API_PORT=$(cat ${key_file} | grep "${API_PORT}" | awk -F= '{print $2}')
        FILE_SERVER_PORT=$(cat ${key_file} | grep "${FILE_SERVER_PORT}" | awk -F= '{print $2}')
        DATA_PATH=$(cat ${key_file} | grep "${DATA_PATH}" | awk -F= '{print $2}')
    else
        echo ".env 环境配置文件不存在，请先run"
        exit 1
    fi
}


# ------------
# Feature Functions
# ------------

build() {
    # 检查image是否存在
    check_image ${IMAGE_NAME} "latest"
    if [ "$?" -eq 0 ]; then
        echo "镜像已存在，尝试删除"
        docker image rm "${IMAGE_NAME}:latest"
        if [ $? -ne 0 ];then
            echo "镜像已被容器使用并运行，无法构建"
            exit 0
        fi
    fi

    cd "./build"

    Build ${IMAGE_NAME} ${RELEASES}

    docker image save ${IMAGE_NAME}:latest > img/${IMAGE_NAME}:latest.dimg
    docker image save ${IMAGE_NAME}:${RELEASES} > img/${IMAGE_NAME}:${RELEASES}.dimg
}


run() {
    _get_ip 

    check_image ${IMAGE_NAME} "latest"
    if [ "$?" -ne 0 ]; then
        docker pull "${IMAGE_RP_USER}/${IMAGE_NAME}:latest"
    fi


    read -p "使用自动获取的ip地址[${IP_ADDR4}]?(y/n) " use_auto_ip
    if [[ "$use_auto_ip" =~ ^[Nn]$ ]]; then
        read -p "请输入IPv4地址: " ipv4
    fi

    read -p "使用默认文件端口[${FILE_SERVER_PORT}]?(y/n) " file_port
    if [[ "$file_port" =~ ^[Nn]$ ]]; then
        read -p "请输入新端口: " FILE_SERVER_PORT
    fi

    read -p "使用默认管理端口[${API_PORT}]?(y/n) " api_port
    if [[ "$api_port" =~ ^[Nn]$ ]]; then
        read -p "请输入新端口: " API_PORT
    fi

    # 检查端口占用情况
    check_port "9993"
    check_port ${FILE_SERVER_PORT}
    check_port ${API_PORT}

    _init_env_file

    if docker compose up -d; then
        echo "启动完成"
    fi

    extract_config

    print_url
}

upgrade() {
        echo "未解决，后续添加"
}

info() {
    # 读取 .env 文件
    extract_env

    extract_config

    cat ./.env.template| grep "IP_ADDR4" | awk -F= '{print $2}'

    # 读取其它配置文件
    print_info
}


resetpwd() {
    docker exec -it ${CONTAINER_NAME} sh -c 'cp /app/ztncui/src/etc/default.passwd /app/ztncui/src/etc/passwd'
    if [ $? -ne 0 ]; then
        echo "重置密码失败"
        exit 1
    fi

    docker restart ${CONTAINER_NAME}
    if [ $? -ne 0 ]; then
        echo "重启服务失败"
        exit 1
    fi

    echo "--------------------------------"
    echo "重置密码成功"
    echo "当前用户名 admin, 密码为 password"
    echo "--------------------------------"
}

# ------------
# Main Functions
# ------------

init() {
    # 检查是否安装docker、docker-compose、docker-buildx
    docker version | grep "Docker Engine" 2>&1 > /dev/null
    if [ $? -ne 0 ]; then 
        echo "你可以通过 https://get.docker.com/ 脚本去安装 Docker"
    fi
}

main() {
    echo "ZeroTier部署脚本 - 请不要修改除了 .env 外的任何文件"
    echo "1. 构建"
    echo "2. 运行"
    echo "3. 更新"
    echo "4. 重置"
    echo "5. 信息"
    echo "*. 退出"
    read -p "请输入数字：" num

    case "$num" in
    1) build;;
    2) run;;
    3) upgrade;;
    4) resetpwd;;
    5) info;;
    *) exit;;
    esac
}

init
main