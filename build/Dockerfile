FROM alpine:3.22 AS builder

WORKDIR /build

ENV TZ=Asia/Shanghai
# TAG 固定版本
ARG TAG="1.16.1"

COPY ./patch /build/patch

# 构建环境准备
RUN apk update \
    && apk add bash git curl clang make pkgconfig openssl-dev openssl-libs-static linux-headers build-base cmake \
    && curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . "$HOME/.cargo/env"

# 构建ZeroTier
RUN git clone https://github.com/zerotier/ZeroTierOne.git \
    && cd ZeroTierOne \
    && git checkout ${TAG} \
    && git submodule update --init --recursive \
    && make -j $(nproc) ZT_NONFREE=1 ZT_STATIC=1 ZT_USE_X64_ASM_SALSA=1 ZT_USE_X64_ASM_ED25519=1 one \
    && make install

# 构建mkworld
RUN cd ZeroTierOne \
    && echo $(pwd) \
    && cp /build/patch/mkworld_custom.cpp . \
    && cp /build/patch/build.sh . \
    && mv mkworld_custom.cpp mkworld.cpp \
    && bash build.sh \
    && mv mkworld /var/lib/zerotier-one \
    && echo "mkworld has been successfully built"

FROM alpine:3.22

EXPOSE 9993

WORKDIR /app

# 拷贝 entrypoint.sh
COPY --from=builder /build/patch/entrypoint.sh /entrypoint.sh
# 拷贝主目录内容
COPY --from=builder /usr/sbin/zerotier-one /app
COPY --from=builder /var/lib/zerotier-one/mkworld /app

RUN ln -s /app/zerotier-one /usr/sbin/zerotier-one \
    && ln -s /app/zerotier-one /usr/sbin/zerotier-idtool \
    && ln -s /app/mkworld /usr/sbin/mkworld \
    && ls -la /usr/sbin \
    && ls -la /app \
    && chmod +x /entrypoint.sh


RUN apk update \
    && apk --no-cache add bash jq curl openssl \
    && rm -rf /var/cache/apk/*

VOLUME [ "/var/lib/zerotier-one" ]

ENTRYPOINT [ "/bin/bash", "/entrypoint.sh" ]
