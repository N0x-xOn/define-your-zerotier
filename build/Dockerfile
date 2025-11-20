FROM alpine:3.22 AS builder

WORKDIR /build

ENV TZ=Asia/Shanghai
# TAG 固定版本
ARG TAG="1.14.2"

COPY ./patch /build/patch

# 构建环境准备
RUN apk update \
    && apk add bash git curl clang make pkgconfig openssl-dev openssl-libs-static linux-headers build-base \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . "$HOME/.cargo/env"

# 构建ZeroTier
RUN git clone https://github.com/zerotier/ZeroTierOne.git \
    && cd ZeroTierOne \
    && git checkout ${TAG} \
    && LDFLAGS="-L/usr/lib" make -j $(nproc) ZT_STATIC=1 \
    && make install \
    && cd ./attic/world \
    && cp /build/patch/mkworld_custom.cpp . \
    && mv mkworld.cpp mkworld.cpp.bak \
    && mv mkworld_custom.cpp mkworld.cpp \
    && bash build.sh \
    && mv mkworld /var/lib/zerotier-one \
    && echo "mkworld has been successfully built"

FROM alpine:3.22

ENV BACK_PATH="/zerotier-one.bak"
ENV ZEROTIER_HOME="/var/lib/zerotier-one"

EXPOSE 9993

WORKDIR /app

# 拷贝ZeroTier主程序
COPY --from=builder /usr/sbin/zerotier-one /usr/sbin/zerotier-one
COPY --from=builder /usr/sbin/zerotier-idtool /usr/sbin/zerotier-idtool
COPY --from=builder /build/patch/entrypoint.sh /entrypoint.sh

# 拷贝主目录内容
COPY --from=builder ${ZEROTIER_HOME} ${BACK_PATH}

RUN apk update \
    && apk --no-cache add bash jq curl openssl \
    && rm -rf /var/cache/apk/*

VOLUME [ "/var/lib/zerotier-one" ]

ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]
