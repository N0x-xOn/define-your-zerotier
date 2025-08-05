#!/bin/sh

set -x 

# 配置路径和端口
ZEROTIER_PATH="/var/lib/zerotier-one"
APP_PATH="/app"
CONFIG_PATH="${APP_PATH}/config"
BACKUP_PATH="/bak"
ZTNCUI_PATH="${APP_PATH}/ztncui"
ZTNCUI_SRC_PATH="${ZTNCUI_PATH}/src"

# 启动 ZeroTier 和 ztncui
function start() {
    echo "Start ztncui and zerotier"
    cd $ZEROTIER_PATH && ./zerotier-one -p$(cat ${CONFIG_PATH}/zerotier-one.port) -d || exit 1
    nohup node ${APP_PATH}/http_server.js &> ${APP_PATH}/server.log & 
    cd $ZTNCUI_SRC_PATH && npm start || exit 1
}

# 初始化 ZeroTier 数据
function init_zerotier_data() {
    echo "Initializing ZeroTier data"

    echo "${ZT_PORT}" > ${CONFIG_PATH}/zerotier-one.port

    # 将/bak目录下的文件恢复
    cp -r ${BACKUP_PATH}/zerotier-one/* $ZEROTIER_PATH

    cd $ZEROTIER_PATH

    # 生成ZeroTier API访问密钥
    openssl rand -hex 16 > authtoken.secret

    # 生成moon.json文件，为便后续使用
    ./zerotier-idtool generate identity.secret identity.public
    ./zerotier-idtool initmoon identity.public > moon.json

    # 保存ZeroTier端口信息
    ZT_PORT=$(cat ${CONFIG_PATH}/zerotier-one.port)

    # 判断IP_ADDR4是否为空
    if [ -n "$IP_ADDR4" ] && [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\",\"$IP_ADDR6/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR4" ]; then
        stableEndpoints="[\"$IP_ADDR4/${ZT_PORT}\"]"
    elif [ -n "$IP_ADDR6" ]; then
        stableEndpoints="[\"$IP_ADDR6/${ZT_PORT}\"]"
    else
        echo "IP_ADDR4 and IP_ADDR6 are both empty!"
        exit 1
    fi

    # 保存ip地址
    echo "$IP_ADDR4" > ${CONFIG_PATH}/ip_addr4
    echo "$IP_ADDR6" > ${CONFIG_PATH}/ip_addr6
    echo "stableEndpoints=$stableEndpoints"

    # 上文中生成的moon.json文件中的stableEndpoints内容为空
    # 这里将我们的planet公网IP填充进去
    # ["ip/port"]
    jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json


    # 这一步是生成moon配置文件
    # 方便能够添加moon节点的设备使用
    ./zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

    # 生成planet
    # @require 必须要当前目录下的 moon.json 文件
    # @return 若无错误，则会输出一个名为 world.bin的文件
    #         并输出该文件的Hex内容
    # @note 在后续的过程中，可以通过 mkworld -b 
    #       查看我们的planet文件（当前目录下必须有名为 world.bin）
    #       可以将生成后的planet重命名复制到当前目录下
    ./mkworld
    if [ $? -ne 0 ]; then
        echo "mkmoonworld failed!"
        exit 1
    fi

    # 保存planet和moon文件
    # TODO 将world.bin 移动为 /dist/planet
    #      将000000984b24cc0a.moon样式的moon文件拷贝到/dist/中
    mkdir -p ${APP_PATH}/dist/
    mv world.bin ${APP_PATH}/dist/planet
    cp *.moon ${APP_PATH}/dist/
    echo "mkmoonworld success!"
}

# 检查并初始化 ZeroTier
function check_zerotier() {
    mkdir -p $ZEROTIER_PATH
    if [ "$(ls -A $ZEROTIER_PATH)" ]; then
        echo "$ZEROTIER_PATH is not empty, starting directly"
    else
        init_zerotier_data
    fi
}

# 初始化 ztncui 数据
function init_ztncui_data() {
    echo "Initializing ztncui data"
    cp -r ${BACKUP_PATH}/ztncui/* $ZTNCUI_PATH

    echo "Configuring ztncui"
    mkdir -p ${CONFIG_PATH}
    echo "${API_PORT}" > ${CONFIG_PATH}/ztncui.port
    cd $ZTNCUI_SRC_PATH
    echo "HTTP_PORT=${API_PORT}" > .env
    echo 'NODE_ENV=production' >> .env
    echo 'HTTP_ALL_INTERFACES=true' >> .env
    echo "ZT_ADDR=localhost:${ZT_PORT}" >> .env
    cp -v etc/default.passwd etc/passwd
    TOKEN=$(cat ${ZEROTIER_PATH}/authtoken.secret)
    echo "ZT_TOKEN=$TOKEN" >> .env
    echo "ztncui configuration successful!"
}

# 检查并初始化 ztncui
function check_ztncui() {
    mkdir -p $ZTNCUI_PATH
    if [ "$(ls -A $ZTNCUI_PATH)" ]; then
        echo "${API_PORT}" > ${CONFIG_PATH}/ztncui.port
        echo "$ZTNCUI_PATH is not empty, starting directly"
    else
        init_ztncui_data
    fi
}

check_zerotier
check_ztncui
start
