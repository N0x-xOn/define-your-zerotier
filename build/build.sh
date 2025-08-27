#!/bin/bash

RELEASES=""
IMAGE_NAME="zerotier-controller"

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

Build() {
    if ! _getReleaseVersion; then
        echo "获取 ZeroTier 版本失败，请检查网络连接或 https://download.zerotier.com/RELEASES/ 状态。"
        return 1
    fi

    if [[ -z ${image_name} && -z ${RELEASES} ]]; then
        return 1
    fi

    # ZeroTier 最新版标签 
    docker buildx build --platform linux/amd64 -t "${IMAGE_NAME}" .
    docker buildx build --platform linux/amd64 -t "${IMAGE_NAME}:${RELEASES}" .
}
