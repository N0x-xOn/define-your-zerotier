#!/bin/bash

source build/build.sh

# 构建所需变量
IMAGE_NAME="define-your-zerotier"
IMAGE_RP_USER="shawing"
ZTN_RP="ZeroTierOne"
ZTN_RP_USER="zerotier"
RELEASES=""

# IP_ADDR*
PUBLIC_IPv4_CHECK_URL="https://ipv4.icanhazip.com/"
PUBLIC_IPv6_CHECK_URL="https://ipv6.icanhazip.com/"

# .env 配置文件内容
IP_ADDR4=""
IP_ADDR6=""
ZTNCUI_PORT="3443" # Ztncui 端口
ZT_PORT="9993" # ZeroTier默认端口,不要修改
DATA_PATH="/data/zerotier" # 默认数据存放

# Global Var
MOON_NAME=""
CONTAINER_SERVICE_NAME="zerotier-server"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------
# Utils Functions
# ------------

info_msg() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success_msg() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

error_msg() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

warn_msg() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

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
    
    if [ -z "${zerotier_release}" ]; then
        return 1
    else
        RELEASES=${zerotier_release}
        return 0
    fi
}

_init_env_file() {
    sed -e "s#__IP_ADDR4__#${IP_ADDR4}#" \
    -e "s#__ZTNCUI_PORT__#${ZTNCUI_PORT}#" \
    -e "s#__DATA_PATH__#${DATA_PATH}#" \
    .env.template > .env
}

_get_ip() {
    info_msg "正在获取公网 IPv4 地址从 ${PUBLIC_IPv4_CHECK_URL}..."
    IP_ADDR4=$(curl -s --connect-timeout 5 ${PUBLIC_IPv4_CHECK_URL})
    if [ -z "${IP_ADDR4}" ]; then
        warn_msg "从 ${PUBLIC_IPv4_CHECK_URL} 获取 IPv4 地址失败。"
        info_msg "尝试备用服务: https://api.ipify.org"
        IP_ADDR4=$(curl -s --connect-timeout 5 https://api.ipify.org)
        if [ -z "${IP_ADDR4}" ]; then
            error_msg "获取公网 IPv4 地址失败。请检查网络连接或稍后手动输入IP地址。"
            return 1
        fi
    fi
    # Simple validation for IP format
    if ! [[ "${IP_ADDR4}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        error_msg "获取到的 IPv4 地址 '${IP_ADDR4}' 格式无效。请检查网络或手动输入。"
        return 1
    fi
    success_msg "获取到的公网 IPv4 地址: ${IP_ADDR4}"
}


# Check docker image
# $1 check target image name 
# $2 image tag
_check_image() {
    local image_name=$1
    local image_tag=$2

    if [ -z "${image_name}" ] || [ -z "${image_tag}" ]; then
        error_msg "内部错误: _check_image 调用时镜像名称或标签为空。"
        return 1
    fi

    info_msg "检查本地是否存在 Docker 镜像 ${image_name}:${image_tag}..."
    if docker image inspect "${image_name}:${image_tag}" &> /dev/null; then
        success_msg "本地已存在镜像 ${image_name}:${image_tag}。"
        return 0 # True, image exists
    else
        info_msg "本地未找到镜像 ${image_name}:${image_tag}。"
        return 1 # False, image does not exist
    fi
}

# $1 des port
_check_port() {
    local port=$1
    local ss_cmd="ss -tulnp"
    if [[ $EUID -ne 0 ]]; then
        ss_cmd="sudo ${ss_cmd}"
    fi

    if ${ss_cmd} | grep -qw ":${port}" ; then
         error_msg "端口 ${port} 已被占用。请检查 '${ss_cmd} | grep -w :${port}' 确定占用进程，并释放该端口或在配置中使用其他端口。"
    fi
}

print_url() {
    echo -e "\n${BLUE}===============================================================${NC}"
    echo -e "${BLUE}                    部署完成 - 访问信息                    ${NC}"
    echo -e "${BLUE}===============================================================${NC}\n"
    if [ -n "${IP_ADDR4}" ] && [ -n "${ZTNCUI_PORT}" ]; then
        echo -e "${GREEN}请访问 Web UI进行配置: ${YELLOW}http://${IP_ADDR4}:${ZTNCUI_PORT}${NC}"
        echo -e "默认用户名：${YELLOW}admin${NC}"
        echo -e "默认密码：${YELLOW}password${NC}"
        warn_msg "请及时修改密码！"
    else
        warn_msg "IP 地址或 API 端口未完全配置，无法生成 Web UI 链接。"
    fi

    echo -e "\n${BLUE}--- Planet和Moon文件信息 ---${NC}"
    if [ -n "${DATA_PATH}" ]; then
         echo -e "Moon配置文件和Planet配置文件位于宿主机路径: ${YELLOW}${DATA_PATH}/dist${NC}"
    fi

    echo -e "\n${BLUE}--- 防火墙提醒 ---${NC}"
    warn_msg "请确保防火墙已放行以下端口："
    echo -e "  - ${YELLOW}${ZT_PORT}/tcp${NC} (ZeroTier)"
    echo -e "  - ${YELLOW}${ZT_PORT}/udp${NC} (ZeroTier)"
    echo -e "  - ${YELLOW}${ZTNCUI_PORT}/tcp${NC} (Web UI)"
    echo -e "\n${BLUE}===============================================================${NC}\n"
}


# ------------
# Pkg Functions
# ------------

_extract_config() {
    _extract() {
        local config_name=$1
        if [ -z "${DATA_PATH}" ] || [ ! -d "${DATA_PATH}/config" ]; then
            warn_msg "在 _extract 中: DATA_PATH 未设置或 ${DATA_PATH}/config 不存在。"
            return
        fi
        if [ ! -f "${DATA_PATH}/config/${config_name}" ]; then
            warn_msg "在 _extract 中: 配置文件 ${DATA_PATH}/config/${config_name} 未找到。"
            return
        fi
        cat "${DATA_PATH}/config/${config_name}" | tr -d '\r'
    }

    local temp_ip4
    temp_ip4=$(_extract "ip_addr4")
    if [ -z "${IP_ADDR4}" ] && [ -n "${temp_ip4}" ]; then
        IP_ADDR4=${temp_ip4}
    fi
    # IP_ADDR6=$(_extract "ip_addr6")

    if [ -n "${DATA_PATH}" ] && [ -d "${DATA_PATH}/dist" ]; then
        MOON_NAME=$(ls "${DATA_PATH}/dist" 2>/dev/null | grep moon | tr -d '\r' | head -n 1)
    else
        # warn_msg "在 _extract_config 中: DATA_PATH 未设置或 ${DATA_PATH}/dist 不存在，无法获取 MOON_NAME。"
        MOON_NAME=""
    fi
}

# 读取.env文件中的配置
_extract_env() {
    local key_file="${PWD}/.env"
    if [ -f "${key_file}" ]; then
        local temp_ip4 api_p f_server_p data_p
        temp_ip4=$(grep -E "^IP_ADDR4=" "${key_file}" | cut -d= -f2-)
        # IP_ADDR6=$(grep -E "^IP_ADDR6=" "${key_file}" | cut -d= -f2-)
        api_p=$(grep -E "^ZTNCUI_PORT=" "${key_file}" | cut -d= -f2-)
        data_p=$(grep -E "^DATA_PATH=" "${key_file}" | cut -d= -f2-)

        [ -n "$temp_ip4" ] && IP_ADDR4="$temp_ip4"
        [ -n "$api_p" ] && ZTNCUI_PORT="$api_p"
        [ -n "$data_p" ] && DATA_PATH="$data_p"

        if [ -z "${ZTNCUI_PORT}" ] || [ -z "${DATA_PATH}" ]; then
             warn_msg ".env 文件部分配置项未能正确加载。请检查文件格式。"
        fi
    else
        error_msg ".env 环境配置文件不存在，请先执行 'run' 命令生成。"
    fi
}

# 函数：根据系统类型静默安装软件包
_install_package() {
    local DEBIAN_PKG_NAME="libreadline-dev"
    local REDHAT_PKG_NAME="readline-devel"

    # 检查是否是 Debian/Ubuntu
    if command -v apt-get &> /dev/null; then
        # 检查软件包是否已安装
        if dpkg -s "$DEBIAN_PKG_NAME" &> /dev/null; then
            return 0
        fi
        sudo apt-get -qq update
        if ! sudo apt-get -qq install -y "$DEBIAN_PKG_NAME"; then
            return 1
        fi
        return 0

    # 检查是否是 Red Hat/CentOS/Fedora
    elif command -v yum &> /dev/null; then
        # 检查软件包是否已安装
        if yum list installed "$REDHAT_PKG_NAME" &> /dev/null; then
            return 0
        fi
        if ! sudo yum install -y "$REDHAT_PKG_NAME"; then
            return 1
        fi
        return 0
    # 检查是否是较新的 Fedora/RHEL (使用 dnf)
    elif command -v dnf &> /dev/null; then
        # 检查软件包是否已安装
        if dnf list installed "$REDHAT_PKG_NAME" &> /dev/null; then
            return 0
        fi
        
        if ! sudo dnf install -y "$REDHAT_PKG_NAME"; then
            return 1
        fi
        return 0
    # 无法识别系统
    else
        return 1
    fi
}

# ------------
# Feature Functions
# ------------

build() {
    info_msg "开始构建 Docker 镜像: ${IMAGE_NAME}"

    info_msg "获取最新的 ZeroTier 版本号..."
    if ! _getReleaseVersion; then
        error_msg "获取 ZeroTier 版本失败，请检查网络连接或 https://download.zerotier.com/RELEASES/ 状态。"
        return 1
    fi
    success_msg "获取到 ZeroTier 最新版本: ${RELEASES}"

    local image_to_check_latest="${IMAGE_NAME}:latest"
    local image_to_check_release="${IMAGE_NAME}:${RELEASES}"
    local image_in_use=false

    if docker ps -a --filter "ancestor=${image_to_check_latest}" --format "{{.ID}}" | read -r || \
       docker ps -a --filter "ancestor=${image_to_check_release}" --format "{{.ID}}" | read -r ; then
        if docker ps -a --filter "ancestor=${image_to_check_latest}" --format "{{.ID}}" | grep -q . || \
           docker ps -a --filter "ancestor=${image_to_check_release}" --format "{{.ID}}" | grep -q . ; then
            image_in_use=true
        fi
    fi


    if ${image_in_use}; then
        error_msg "镜像 ${IMAGE_NAME} (latest or ${RELEASES}) 正被一个或多个容器使用。请先停止并移除相关容器 (e.g., 'docker compose down') 才能重建镜像。"
        return 1
    else
        info_msg "检查并尝试移除旧的本地镜像 (${image_to_check_latest}, ${image_to_check_release})..."
        docker image rm "${image_to_check_latest}" 2>/dev/null || true
        docker image rm "${image_to_check_release}" 2>/dev/null || true
        success_msg "旧的本地镜像已尝试移除 (如果存在且未使用)。"
    fi


    if [ ! -d "build/" ] || [ ! -f "build/build.sh" ] || [ ! -f "build/Dockerfile" ]; then
        error_msg "构建所需文件 (build/build.sh, build/Dockerfile) 未找到。无法继续构建。"
        return 1
    fi
    
    cd build/
    info_msg "进入 'build/' 目录，开始执行实际构建过程 (Build ${IMAGE_NAME} ${RELEASES})..."

    

    if ! Build "${IMAGE_NAME}" "${RELEASES}"; then 
        error_msg "Docker 镜像构建失败。请检查 './build.sh' 脚本的输出。"
        cd ..
        return 1
    fi
    success_msg "Docker 镜像 ${IMAGE_NAME}:${RELEASES} 和 ${IMAGE_NAME}:latest 构建成功。"
    

    read -p "是否保存镜像？[Y/n]:" save
    if [[ "${save}" =~ ^[Yy]$ ]]; then
        info_msg "正在保存镜像到 .dimg 文件..."
        mkdir -p img/
        local save_latest_path="img/${IMAGE_NAME}_latest.dimg"
        local save_release_path="img/${IMAGE_NAME}_${RELEASES}.dimg"

        if docker image save "${IMAGE_NAME}:latest" -o "${save_latest_path}" && \
        docker image save "${IMAGE_NAME}:${RELEASES}" -o "${save_release_path}"; then
            success_msg "镜像已保存到 'build/${save_latest_path}' 和 'build/${save_release_path}'。"
        else
            warn_msg "保存镜像到 .dimg 文件失败。"
        fi
    fi

    cd ..
    info_msg "构建流程完成。"
}


run() {
    if ! _get_ip && [[ -z "$IP_ADDR4" ]]; then
         info_msg "无法自动获取IP地址。"
    fi

    _check_image "${IMAGE_NAME}" "latest"
    if [ "$?" -ne 0 ]; then
        info_msg "本地未找到镜像 ${IMAGE_NAME}:latest，尝试从 ${IMAGE_RP_USER}/${IMAGE_NAME}:latest 拉取..."
        if ! docker pull "${IMAGE_RP_USER}/${IMAGE_NAME}:latest"; then
            error_msg "拉取镜像 ${IMAGE_RP_USER}/${IMAGE_NAME}:latest 失败。请检查网络或尝试手动构建 (选项 1)。"
        else
            success_msg "镜像 ${IMAGE_RP_USER}/${IMAGE_NAME}:latest 拉取成功。"
        fi
    else
        info_msg "本地已存在镜像 ${IMAGE_NAME}:latest。"
    fi

    echo -e "\n${BLUE}--- IP 地址配置 ---${NC}"
    local current_ip_prompt="是否使用自动获取的公网 IPv4 地址 [${GREEN}${IP_ADDR4}${YELLOW}]? (y/n): "
    if [ -z "${IP_ADDR4}" ]; then
        current_ip_prompt="公网 IPv4 地址未自动获取。是否现在手动输入? (y/n): "
    fi
    read -p "$(echo -e "${YELLOW}${current_ip_prompt}${NC}")" use_auto_ip_confirm
    
    if [[ "$use_auto_ip_confirm" =~ ^[Nn]$ ]] || ([ -z "${IP_ADDR4}" ] && [[ "$use_auto_ip_confirm" =~ ^[Yy]$ ]]); then
        read -p "$(echo -e "${YELLOW}请输入您的公网 IPv4 地址: ${NC}")" IP_ADDR4_MANUAL
        if [ -n "${IP_ADDR4_MANUAL}" ]; then
            IP_ADDR4=${IP_ADDR4_MANUAL}
        elif [ -z "${IP_ADDR4}" ]; then 
            error_msg "未提供公网 IPv4 地址。无法继续。"
        fi
    fi
    info_msg "将使用的 IPv4 地址: ${IP_ADDR4}"

    echo -e "\n${BLUE}--- 端口配置 ---${NC}"
    read -p "$(echo -e "${YELLOW}是否使用默认API管理端口 [${GREEN}${ZTNCUI_PORT}${YELLOW}]? (y/n): ${NC}")" use_default_api_port
    if [[ "$use_default_api_port" =~ ^[Nn]$ ]]; then
        read -p "$(echo -e "${YELLOW}请输入新的API管理端口 (例如 3444): ${NC}")" NEW_ZTNCUI_PORT
        if [[ "${NEW_ZTNCUI_PORT}" =~ ^[0-9]+$ ]] && [ "${NEW_ZTNCUI_PORT}" -gt 0 ] && [ "${NEW_ZTNCUI_PORT}" -lt 65536 ]; then
            ZTNCUI_PORT=${NEW_ZTNCUI_PORT}
        elif [ -n "${NEW_ZTNCUI_PORT}" ]; then
            warn_msg "无效的端口号 '${NEW_ZTNCUI_PORT}'。将使用默认端口 ${ZTNCUI_PORT}。"
        fi
    fi
    info_msg "将使用的API管理端口: ${ZTNCUI_PORT}"

    echo -e "\n${BLUE}--- 数据路径配置 ---${NC}"
    read -p "$(echo -e "${YELLOW}ZeroTier 数据将默认存储在 [${GREEN}${DATA_PATH}${YELLOW}]，是否修改? (y/n): ${NC}")" modify_data_path_confirm
    if [[ "$modify_data_path_confirm" =~ ^[Yy]$ ]]; then
        read -e -p "$(echo -e "${YELLOW}请输入新的数据存储绝对路径 (例如 /opt/zerotier-data): ${NC}")" NEW_DATA_PATH
        if [ -n "${NEW_DATA_PATH}" ]; then
            if [[ "${NEW_DATA_PATH}" == /* ]]; then
                DATA_PATH=${NEW_DATA_PATH}
            else
                warn_msg "输入的路径 '${NEW_DATA_PATH}' 不是绝对路径。将使用默认路径 ${DATA_PATH}。"
            fi
        fi
    fi
    # 确保目录存在
    if [ ! -d "${DATA_PATH}" ]; then
        info_msg "数据路径 ${DATA_PATH} 不存在，正在创建..."
        # Attempt to create with sudo if not root
        local mkdir_cmd="mkdir -p"
        local chown_cmd="chown $(id -u):$(id -g)"
        if [[ $EUID -ne 0 ]]; then
            mkdir_cmd="sudo ${mkdir_cmd}"
            chown_cmd="sudo ${chown_cmd}"
        fi

        if ${mkdir_cmd} "${DATA_PATH}" && ${chown_cmd} "${DATA_PATH}"; then 
            success_msg "数据路径 ${DATA_PATH} 创建成功。"
        else
            error_msg "创建数据路径 ${DATA_PATH} 失败。请检查权限或手动创建并设置正确权限。"
        fi
    fi
    info_msg "将使用的数据路径: ${DATA_PATH}"


    info_msg "检查端口占用情况..."
    _check_port ${ZT_PORT}
    _check_port ${ZTNCUI_PORT}
    success_msg "所需端口未被占用。"


    _init_env_file
    success_msg ".env 配置文件已生成/更新。"

    info_msg "正在启动服务 (docker compose up -d)..."
    if docker compose up -d; then
        success_msg "服务启动命令已执行。请等待几秒钟让服务完全启动。"
        sleep 5 # Give services time to start
        # Check if containers are running
        if ! docker compose ps --filter "status=running" | grep -q "${CONTAINER_SERVICE_NAME}"; then 
            warn_msg "服务 '${CONTAINER_SERVICE_NAME}' 可能未能成功启动。请检查 'docker compose logs ${CONTAINER_SERVICE_NAME}'。"
        else
            success_msg "服务 '${CONTAINER_SERVICE_NAME}' 似乎已成功启动。"
        fi
    else
        error_msg "服务启动失败。请检查 'docker compose logs' 获取更多信息。"
    fi

    info_msg "尝试从运行中的服务提取配置..."
    _extract_config 
    if [ -z "${MOON_NAME}" ]; then
        warn_msg "未能从服务中提取完整的配置信息 (MOON_NAME missing)。下载链接可能不完整。"
    else
        success_msg "配置提取完成。"
    fi
    print_url
}

# 更新ZeroTier
upgrade() {
        warn_msg "更新功能当前未实现，后续添加。"
}

# 打印配置信息
info() {
    info_msg "正在加载配置信息..."
    if [ ! -f ".env" ]; then
        warn_msg ".env 文件不存在。部分信息可能无法显示。请先执行 'run' 命令生成 .env 文件。"
    else
        # Load variables from .env to display them
        # Using _extract_env which populates global vars
        _extract_env
        success_msg ".env 文件已加载。"
    fi
    
    echo -e "\n${BLUE}--- 解析后的主要配置值 (来自 .env 或默认值) ---${NC}"
    echo -e "  ${GREEN}公网 IPv4 地址:${NC} ${YELLOW}${IP_ADDR4:-未设置}${NC}"
    echo -e "  ${GREEN}API 管理端口:${NC} ${YELLOW}${ZTNCUI_PORT:-未设置}${NC}"
    echo -e "  ${GREEN}ZeroTier 默认端口:${NC} ${YELLOW}${ZT_PORT:-9993}${NC} (UDP/TCP)"
    echo -e "  ${GREEN}数据存储路径:${NC} ${YELLOW}${DATA_PATH:-未设置}${NC}"

    # Information from _extract_config (reads from ${DATA_PATH}/config/*)
    # This reflects the state after 'run' and service interaction
    if [ -n "${DATA_PATH}" ] && [ -d "${DATA_PATH}/config" ] && [ "$(ls -A ${DATA_PATH}/config 2>/dev/null)" ]; then
        info_msg "尝试从 ${DATA_PATH}/config/ 读取运行时配置..."
        _extract_config
        echo -e "\n${BLUE}--- 从 ${DATA_PATH}/config/ 读取的运行时值 ---${NC}"
        echo -e "  ${GREEN}Moon Name:${NC} ${YELLOW}${MOON_NAME:-未找到或未生成}${NC}"
    else
        warn_msg "运行时配置文件目录 (${DATA_PATH}/config/) 未找到或为空。MOON_NAME 可能未生成。"
    fi
    
    echo -e "\n${BLUE}--- 访问链接 (基于以上配置) ---${NC}"
    print_url # Re-use print_url for consistent output
    echo ""
}

# 重置密码
resetpwd() {
    info_msg "正在尝试重置密码..."
    if [ -z "${CONTAINER_SERVICE_NAME}" ]; then
        error_msg "内部错误: CONTAINER_SERVICE_NAME 未定义。"
        return 1
    fi

    local container_id
    # Get the first running container for the service
    container_id=$(docker compose ps -q "${CONTAINER_SERVICE_NAME}" 2>/dev/null | head -n 1)

    if [ -z "${container_id}" ]; then
        error_msg "无法找到服务 '${CONTAINER_SERVICE_NAME}' 运行中的容器。请确保服务已通过 'run' 命令启动。"
        return 1
    fi
    
    info_msg "找到容器 ID: ${container_id} for service ${CONTAINER_SERVICE_NAME}"

    # The path inside the container needs to be correct. Original: /app/ztncui/src/etc/default.passwd
    local default_passwd_path="/app/ztncui/src/etc/default.passwd"
    local passwd_path="/app/ztncui/src/etc/passwd"
    info_msg "将在容器内执行: cp ${default_passwd_path} ${passwd_path}"
    if docker exec "${container_id}" sh -c "cp '${default_passwd_path}' '${passwd_path}'"; then
        success_msg "密码文件已在容器内重置。"
    else
        error_msg "在容器内执行重置密码命令失败。请检查路径和服务状态。"
        return 1
    fi

    info_msg "正在重启服务 '${CONTAINER_SERVICE_NAME}'..."
    if docker compose restart "${CONTAINER_SERVICE_NAME}"; then
        success_msg "服务 '${CONTAINER_SERVICE_NAME}' 重启成功。"
    else
        error_msg "重启服务 '${CONTAINER_SERVICE_NAME}' 失败。"
        return 1
    fi

    echo -e "\n${GREEN}--------------------------------${NC}"
    echo -e "${GREEN}      密码重置成功！      ${NC}"
    echo -e "当前用户名: ${YELLOW}admin${NC}, 密码为: ${YELLOW}password${NC}"
    echo -e "${GREEN}--------------------------------${NC}"
    warn_msg "请尽快登录并修改密码。"
}

# ------------
# Main Functions
# ------------

init() {
    info_msg "开始初始化检查..."

    # Check for essential commands
    info_msg "检查必要的工具 (curl, ss)..."
    if ! command -v curl &> /dev/null; then
        error_msg "'curl' 命令未找到。请安装 curl 后再运行此脚本。"
    fi
    if ! command -v ss &> /dev/null; then
        distro_info=$(grep PRETTY_NAME /etc/os-release 2>/dev/null || echo "Unknown")
        error_msg "'ss' 命令未找到 (通常由 'iproute2' 或 'iproute' 包提供)。请安装它后再运行此脚本. Detected OS: ${distro_info}"
    fi

    _install_package

    success_msg "必要的工具已找到。"

    # 检查Docker是否安装
    info_msg "检查 Docker 是否已安装..."
    if ! command -v docker &> /dev/null; then
        warn_msg "Docker 未安装。"
        echo -ne "${YELLOW}是否尝试使用官方脚本安装 Docker? (y/n): ${NC}"
        read -r install_docker_confirm
        if [[ "$install_docker_confirm" =~ ^[Yy]$ ]]; then
            info_msg "开始安装 Docker... 这可能需要一些时间。"
            local docker_installed_successfully=false
            for i in {1..3}; do
                info_msg "尝试安装 Docker (第 $i 次)..."
                local install_script_url="https://get.docker.com"
                if [[ $EUID -ne 0 ]]; then
                    info_msg "将使用 'sudo bash' 执行 Docker 安装脚本。"
                    if curl -fsSL "${install_script_url}" | sudo bash -s docker --mirror Aliyun; then
                        success_msg "Docker 安装脚本执行完毕。"
                        docker_installed_successfully=true
                    else
                        warn_msg "Docker 安装脚本执行失败 (第 $i 次)。"
                    fi
                else
                    info_msg "将以 root 用户执行 Docker 安装脚本。"
                    if curl -fsSL "${install_script_url}" | bash -s docker --mirror Aliyun; then
                        success_msg "Docker 安装脚本执行完毕。"
                        docker_installed_successfully=true
                    else
                        warn_msg "Docker 安装脚本执行失败 (第 $i 次)。"
                    fi
                fi

                if ${docker_installed_successfully}; then
                    if command -v docker &> /dev/null; then
                        success_msg "Docker 命令已可用。"
                        if [[ $EUID -ne 0 ]]; then
                            info_msg "尝试将当前用户 $USER 加入 'docker' 组..."
                            if sudo usermod -aG docker "$USER"; then
                                success_msg "用户 $USER 已加入 'docker' 组。请重新登录或执行 'newgrp docker' 使更改生效。"
                            else
                                warn_msg "无法自动将用户 $USER 加入 'docker' 组。请手动执行: sudo usermod -aG docker $USER"
                            fi
                        fi
                        if command -v systemctl &> /dev/null; then
                            info_msg "尝试启动并启用 Docker 服务..."
                            if sudo systemctl start docker && sudo systemctl enable docker; then
                                success_msg "Docker 服务已启动并启用。"
                            else
                                warn_msg "启动或启用 Docker 服务失败。请手动检查。"
                            fi
                        fi
                        break
                    else
                        warn_msg "Docker 安装脚本已执行，但 'docker' 命令仍不可用。可能需要重新登录或检查 PATH。"
                        docker_installed_successfully=false
                    fi
                fi

                if ! ${docker_installed_successfully} && [ $i -lt 3 ]; then
                    info_msg "5秒后重试..."
                    sleep 5
                fi
            done

            if ! ${docker_installed_successfully} || ! command -v docker &> /dev/null; then
                 error_msg "Docker 安装失败。请参考 https://docs.docker.com/engine/install/ 手动安装，或检查 https://status.1panel.top/status/docker 获取镜像源信息，然后重新运行此脚本。"
            fi
        else
            error_msg "Docker 未安装。请先安装 Docker 后再运行此脚本。"
        fi
    else
        success_msg "Docker 已安装: $(docker --version | head -n 1)"
    fi

    # 检查Docker服务是否运行
    info_msg "检查 Docker 服务状态..."
    sleep 2
    if ! docker info > /dev/null 2>&1; then
        warn_msg "Docker 服务未运行或当前用户无权限访问 Docker 守护进程。"
        if command -v systemctl &> /dev/null && systemctl list-units --type=service --state=active | grep -q docker.service; then
             warn_msg "Docker 服务似乎已安装但未正确运行或配置。请检查 'sudo systemctl status docker'。"
             warn_msg "如果刚将用户添加到 'docker' 组，您可能需要重新登录或执行 'newgrp docker'。"
        fi
        
        echo -ne "${YELLOW}是否尝试启动 Docker 服务 (可能需要sudo权限)? (y/n): ${NC}"
        read -r start_docker_service_confirm
        if [[ "$start_docker_service_confirm" =~ ^[Yy]$ ]]; then
            local start_cmd_prefix=""
            if [[ $EUID -ne 0 ]]; then
                start_cmd_prefix="sudo "
            fi

            if command -v systemctl &> /dev/null; then
                info_msg "尝试使用 systemctl 启动 Docker 服务..."
                if ${start_cmd_prefix}systemctl start docker && ${start_cmd_prefix}systemctl enable docker; then
                    success_msg "Docker 服务启动/启用命令已执行。"
                    sleep 3 #给服务一点启动时间
                    if ! docker info > /dev/null 2>&1; then
                        error_msg "启动 Docker 服务后，仍无法连接。请手动检查 Docker 服务状态及用户权限 ('newgrp docker' 或重新登录)。"
                    else
                        success_msg "Docker 服务已成功连接。"
                    fi
                else
                    error_msg "使用 systemctl 启动 Docker 服务失败。请手动检查并启动 Docker 服务。"
                fi
            elif command -v service &> /dev/null; then
                 info_msg "尝试使用 service 命令启动 Docker 服务..."
                 if ${start_cmd_prefix}service docker start; then
                    success_msg "Docker 服务启动命令已执行。"
                    sleep 3
                    if ! docker info > /dev/null 2>&1; then
                        error_msg "启动 Docker 服务后，仍无法连接。请手动检查 Docker 服务状态及用户权限。"
                    else
                        success_msg "Docker 服务已成功连接。"
                    fi
                 else
                    error_msg "使用 service 命令启动 Docker 服务失败。请手动检查并启动 Docker 服务。"
                 fi
            else
                warn_msg "无法找到 systemctl 或 service 命令，请手动启动 Docker 服务。"
                error_msg "Docker 服务未运行。请启动 Docker 服务后再运行此脚本。"
            fi
        else
             error_msg "Docker 服务未运行或无法访问。请启动 Docker 服务并确保用户权限正确后再运行此脚本。"
        fi
    else
        success_msg "Docker 服务正在运行且可访问。"
    fi

    # 检查 Docker Compose (plugin)
    info_msg "检查 Docker Compose (plugin)..."
    if ! docker compose version &> /dev/null; then
        warn_msg "Docker Compose plugin (docker compose) 未找到。"
        warn_msg "此脚本需要 Docker Compose V2 (plugin)。"
        warn_msg "通常，通过 get.docker.com 安装的最新版 Docker 会包含它。"
        warn_msg "如果您的 Docker 版本较旧或安装方式不同，请参考: https://docs.docker.com/compose/install/"
        error_msg "请确保 Docker Compose plugin 已正确安装并可用。"
    else
        success_msg "Docker Compose plugin 已安装: $(docker compose version | head -n 1)"
    fi

    # 检查 Docker Buildx
    info_msg "检查 Docker Buildx..."
    if ! docker buildx version &> /dev/null; then
        warn_msg "Docker Buildx 未找到或无法执行。"
        warn_msg "Docker Buildx 用于构建镜像，是现代 Docker 的一部分。"
        warn_msg "如果构建功能失败，请确保您的 Docker 安装完整且最新。"
    else
        success_msg "Docker Buildx 可用: $(docker buildx version | head -n 1)"
    fi

    success_msg "初始化检查完成。所有必要组件似乎已就绪。"
}

main() {
    echo -e "\n${BLUE}=====================================================${NC}"
    echo -e "${BLUE}        ZeroTier 自建Planet/Moon服务器部署脚本        ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "项目地址: https://github.com/Xiwin/define-your-zerotier"
    echo -e "\n${YELLOW}重要提示: 请不要修改除了 .env 之外的任何脚本文件，除非您知道自己在做什么。${NC}\n"

    echo -e "${GREEN}可用操作：${NC}"
    echo -e "  ${YELLOW}1)${NC} 构建镜像 (Build)"
    echo -e "  ${YELLOW}2)${NC} 运行服务 (Run)"
    echo -e "  ${YELLOW}3)${NC} 更新服务 (Upgrade) ${RED}(功能未完成)${NC}"
    echo -e "  ${YELLOW}4)${NC} 重置密码 (Reset Password)"
    echo -e "  ${YELLOW}5)${NC} 显示信息 (Info)"
    echo -e "  ${YELLOW}*)${NC} 退出 (Exit)"
    echo -ne "${BLUE}请输入操作对应的数字: ${NC}"
    read -r num

    case "$num" in
    1)
        info_msg "开始执行构建任务..."
        build
        ;;
    2)
        info_msg "开始执行运行任务..."
        run
        ;;
    3)
        upgrade
        ;;
    4)
        info_msg "开始执行重置密码任务..."
        resetpwd
        ;;
    5)
        info_msg "开始执行显示信息任务..."
        info
        ;;
    *)
        info_msg "退出脚本。"
        exit 0
        ;;
    esac
}

init
main