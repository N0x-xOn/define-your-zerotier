FROM debian:bookworm-slim AS builder

WORKDIR /app

ADD ./patch/entrypoint.sh /app/entrypoint.sh
ADD ./patch/mkworld_custom.cpp /app/patch/mkworld_custom.cpp
ADD ./patch/cargo_config /app/cargo_config

ENV TZ=Asia/Shanghai
ENV GHPROXY="https://ghfast.top/"
ENV TAG=main
ENV DEBIAN_FRONTEND=noninteractive

# Rustup 制备镜像地址
ENV RUSTUP_UPDATE_ROOT=https://mirrors.aliyun.com/rustup/rustup
ENV RUSTUP_DIST_SERVER=https://mirrors.aliyun.com/rustup


# init tool
RUN set -x \
    && sed -i 's@deb.debian.org@mirrors.aliyun.com@g' \
    /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y git python3 npm make \
    linux-headers-$(uname -r) \
    curl libpq-dev pkg-config libssl-dev jq build-essential clang \
    protobuf-compiler libprotobuf-dev \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y\
    && . "$HOME/.cargo/env" \
    && cat /app/cargo_config > "$HOME/.cargo/config" \
    && echo "env prepare success!"

# make zerotier-one
RUN set -x\
    # 编译ZeroTier-One
    && git clone "${GHPROXY}https://github.com/zerotier/ZeroTierOne.git" \
    && cd ZeroTierOne \
    && git checkout ${TAG} \
    # 编译ZeroTier控制器版本
    && make ZT_CONTROLLER=1 \
    # make install 主要用以获取zerotier-one.te文件内容
    && make install \
    && cd ./attic/world \
    && cp /app/patch/mkworld_custom.cpp .\
    && mv mkworld.cpp mkworld.cpp.bak \
    && mv mkworld_custom.cpp mkworld.cpp \
    && sh build.sh \
    && mv mkworld /var/lib/zerotier-one \
    && echo "mkworld build success!"

#make ztncui 
RUN set -x \
    && mkdir /app -p \
    && cd /app \
    && git clone --progress "${GHPROXY}https://github.com/key-networks/ztncui.git" \
    && cd /app/ztncui/src \
    && npm config set registry https://registry.npmmirror.com \
    && npm install -g node-gyp \
    && npm install \
    && echo "ztncui build success!" \
    && ls -la /app/ztncui 

FROM debian:bookworm-slim

WORKDIR /app

ENV TZ=Asia/Shanghai

ENV IP_ADDR4=""
ENV IP_ADDR6=""

ENV ZT_PORT=9993
ENV API_PORT=3443

COPY --from=builder /app/ztncui /bak/ztncui

# ZeroTier 相关文件
COPY --from=builder /var/lib/zerotier-one /bak/zerotier-one
COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /app/ZeroTierOne/zerotier-idtool /usr/sbin/zerotier-idtool

COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh

RUN set -x \
    && sed -i 's@deb.debian.org@mirrors.aliyun.com@g' \
    /etc/apt/sources.list.d/debian.sources \
    && apt-get update -qq \
    && apt-get install -qq npm curl jq openssl libc-dev libpq5 -y \
    && mkdir /app/config -p 

VOLUME [ "/app/dist", "/app/ztncui", "/var/lib/zerotier-one", "/app/config"]

ENTRYPOINT ["/bin/bash","/app/entrypoint.sh"]