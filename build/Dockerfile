FROM debian:bookworm-slim AS builder

# 构建参数：是否使用国内镜像源
# 默认使用，Github Action 不使用
ARG USE_CHINA_MIRROR=true

WORKDIR /app

COPY ./patch/entrypoint.sh /app/entrypoint.sh
COPY ./patch/mkworld_custom.cpp /app/patch/mkworld_custom.cpp
COPY ./patch/cargo_config /app/cargo_config
COPY ./patch/check.sh /app/check.sh

ENV TZ=Asia/Shanghai
ENV GHPROXY="https://ghfast.top/"
ENV TAG=main
ENV DEBIAN_FRONTEND=noninteractive

# init tool
RUN set -x \
    && if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        sed -i 's@deb.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources; \
    fi \
    && apt-get update \
    && apt-get install -y git python3 npm make \
    curl libpq-dev pkg-config libssl-dev jq build-essential clang \
    protobuf-compiler libprotobuf-dev \
    && (apt-get install -y linux-headers-$(uname -r) || \
        apt-get install -y linux-headers-generic || \
        apt-get install -y linux-headers-amd64) \
    && if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        export RUSTUP_UPDATE_ROOT=https://mirrors.aliyun.com/rustup/rustup; \
        export RUSTUP_DIST_SERVER=https://mirrors.aliyun.com/rustup; \
    fi \
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

FROM debian:bookworm-slim AS runtime

WORKDIR /app

ENV TZ=Asia/Shanghai

ENV IP_ADDR4=""
ENV IP_ADDR6=""

ENV ZTNCUI_PORT=3443
ENV ZT_PORT=9993

COPY --from=builder /app/ztncui /bak/ztncui
COPY --from=builder /var/lib/zerotier-one /bak/zerotier-one

# ZeroTier 相关文件
COPY --from=builder /app/ZeroTierOne/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /app/ZeroTierOne/zerotier-idtool /usr/sbin/zerotier-idtool

COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh
COPY --from=builder /app/check.sh /app/check.sh

RUN set -x \
    && if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        sed -i 's@deb.debian.org@mirrors.aliyun.com@g' /etc/apt/sources.list.d/debian.sources; \
    fi \
    && apt-get update -qq \
    # 更新镜像存在软件包，确保所有软件包均为当时最新版
    && apt-get -y -qq upgrade \
    # entrypoint 和 check 脚本依赖jq
    # authsecret 密钥生成依赖openssl
    # ZeroTier 依赖 libpq5
    # ztncui 依赖 npm
    && apt-get install -y -qq --no-install-recommends npm curl jq openssl libpq5 \
    && mkdir -p /app/config \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "/bin/bash", "/check.sh" ]

VOLUME [ "/app/dist", "/app/ztncui", "/var/lib/zerotier-one", "/app/config"]

ENTRYPOINT ["/bin/bash","/app/entrypoint.sh"]