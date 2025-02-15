#!/bin/bash

# $1 image name
# $2 image release
# ret 1 or 0
Build() {
    local image_name=$1
    local image_release=$2

    if [[ -z ${image_name} && -z ${image_release} ]]; then
        return 1
    fi

    # ZeroTier 最新版标签 
    docker buildx build --platform linux/amd64 -t "$1:latest" .
    docker buildx build --platform linux/amd64 -t "$1:${image_release}" .
}
