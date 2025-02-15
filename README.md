## 概述

该库的作用主要是用以构建和部署自己的ZeroTier服务器。在默认情况下的应用中

1. 我们只能根据官方DOC去配置Moon服务器，但是因为Moon服务器的握手还是依赖于官方的Planet服务器。但官方的Planet服务器部署在国外，很多时候都会出现访问失败的情况
2. 在某些设备上，我们无法连接Moon服务器
3. 自行部署Planet服务器在国内是很好的解决方案

## 使用

```shell
git clone 

cd define-your-zerotier
chmod +x ./deploy.sh
sudo deploy.sh
```

`deploy.sh` 部署脚本，自带6个功能：

1. 构建: 构建本地镜像并导出
2. 运行: 拉取远程镜像并运行
3. 更新: 通过Compose拉取最新镜像并更新
4. 配置: 设置运行配置
5. 打印信息: file下载路径、planet key 和 moon 名称
6. 重置密码: 重置Ztncui管理面板账号密码

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