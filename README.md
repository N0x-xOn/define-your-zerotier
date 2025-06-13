## 概述

该库的作用主要是用以构建和部署自己的ZeroTier服务器。在缺省情况下：

1. 没有自主性，需要通过ZeroTier官网进行管理
2. 在Mac设备上，无法连接Moon服务器
3. Moon 设备的握手需要通过planet进行，默认的planet服务器都在国外

## 使用

```shell
git clone https://github.com/Xiwin/define-your-zerotier.git

cd define-your-zerotier
chmod +x ./deploy.sh
sudo deploy.sh
```

`deploy.sh` 部署脚本，自带6个功能：

1. 构建: 构建镜像会导出一份本地镜像
2. 运行: 拉取远程镜像并运行
3. 配置: 设置运行配置
4. 打印信息: file下载路径、planet key 和 moon 名称
5. 重置密码: 重置Ztncui管理面板账号密码

> 注意1：主机映射9993/tcp 和 9993/udp 端口不可更改。若出现，9993端口冲突，请优先考虑ZeroTier，若Planet的端口不为9993，Client将无法连接。

> 注意2：可以直接使用sftp或scp工具下载 planet 到本地，无需开启文件下载端口。文件下载端口仅仅适用于脚本化部署客户端使用。

## 目录结构

```shell
.
├── README.md
├── build # 构建docker镜像相关文件
│   ├── Dockerfile
│   ├── build.sh
│   └── patch
│       ├── entrypoint.sh
│       ├── http_server.js
│       └── mkworld_custom.cpp
├── deploy.sh # 脚本化部署流程
├── docker-compose.yaml # 通过Compose管理Docker容器
└── img # 构建后save和load目录
```