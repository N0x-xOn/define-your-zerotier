#!/bin/bash

# 该脚本用以生成planet文件

# 生成planet段
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

    # 上文中生成的moon.json文件中的stableEndpoints内容为空
    # 这里将我们的planet公网IP填充进去
    # ["ip/port"]
    jq --argjson newEndpoints "$stableEndpoints" '.roots[0].stableEndpoints = $newEndpoints' moon.json > temp.json && mv temp.json moon.json


    # 这一步是生成moon配置文件
    # 方便能够添加moon节点的设备使用
    zerotier-idtool genmoon moon.json && mkdir -p moons.d && cp ./*.moon ./moons.d

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