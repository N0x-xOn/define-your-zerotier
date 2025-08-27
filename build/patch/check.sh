#!/bin/bash

# 检查依赖
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed"
    exit 1
fi

# 检查Token文件是否存在
TOKEN_FILE="/var/lib/zerotier-one/authtoken.secret"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Error: Token file not found: $TOKEN_FILE"
    exit 1
fi

# 获取Token
TOKEN=$(cat "$TOKEN_FILE")

# 构建curl请求
resp=$(curl -s "http://localhost:9993/status" -H "X-ZT1-AUTH: ${TOKEN}")

# 检查curl是否成功
if [ $? -ne 0 ]; then
    echo "Error: Failed to connect to ZeroTier API"
    exit 1
fi

# 检查响应是否为有效JSON
if ! jq -e . <<< "$resp" >/dev/null 2>&1; then
    echo "Error: Invalid JSON response from ZeroTier API"
    echo "Response: $resp"
    exit 1
fi

# 可选：显示详细信息（取消注释下行以显示完整响应）
# echo $resp

# 尝试解析信息
# online 应该为 true 或没有该字段
online=$(jq -r '.online // empty' <<< "$resp")

echo "ZeroTier status check - online: $online"

if [ "$online" = "true" ] || [ -z "$online" ]; then
  echo "ZeroTier is online"
  exit 0
else
  echo "ZeroTier is offline"
  exit 1
fi
