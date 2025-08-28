#!/bin/bash

# _request
_request() {
    local METHOD=$1
    local ENDPOINT="http://127.0.0.1:9993/$2"
    local DATA=$3

    curl -sL -X $METHOD "$ENDPOINT" -H "X-ZT1-AUTH: ${TOKEN}" -d "$DATA"
}

# _createNetwork 
# 函数原型
# curl -X POST "http://localhost:9993/controller/network/${NODEID}______" -H "X-ZT1-AUTH: ${TOKEN}" -d {}
_createNetwork() {
    local DATA='{}'
    _request POST "controller/network/${NODEID}______" "$DATA" 
}

# 本脚本用以测试容器是否成功启动
TOKEN=$(cat /var/lib/zerotier-one/authtoken.secret)
NODEID=$(_request GET "status" | jq -r ".address")
NID=$(_createNetwork | jq -r ".id")

echo "${TOKEN}"
echo "${NODEID}"
echo "${NID}"
