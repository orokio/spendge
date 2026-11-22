# 后端部署计划（spendge server）

> 状态：待执行 ｜ 最后更新：2026-11-22 ｜ 适用主机：腾讯云 Ubuntu 24.04（124.223.27.87）

## 1. 概述

为 spendge App 部署后端服务。代码位于 spendge/server（Flask），采用 nginx 反向代理 + gunicorn + MySQL 8.0 的单机架构。基础软件采用"源码/二进制包放 package、安装到 local"的自管理方式，便于版本控制与后续容器化。

### 架构

    用户浏览器
       │ HTTP/HTTPS
       ▼
    nginx（反向代理）   测试 8080/8443 → 备案后 80/443
       │ proxy_pass 127.0.0.1:8000
       ▼
    gunicorn + Flask（2 worker）   仅 127.0.0.1:8000
       │
       ▼
    MySQL 8.0   仅 127.0.0.1:3306

## 2. 环境基线

| 项 | 值 |
|---|---|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| CPU | 2 vCPU |
| 内存 | 1.9G + swap 1.9G |
| 磁盘 | 50G（可用约 35G） |
| 公网 IP | 124.223.27.87 |
| 域名 | www.orokio.com（ICP 备案进行中） |
| 已装服务 | 无 nginx / 无 mysql |

已占用端口（需规避）：9000（python3，公网）、9001、9003、3080、22、53。

## 3. 目录规划

    /home/ubuntu/
    ├── spendge/          # 代码仓库（server/、docs/）
    ├── package/          # 源包 / 二进制压缩包（已建）
    ├── local/            # 安装前缀：local/nginx、local/mysql（已建）
    ├── data/mysql/       # MySQL 数据目录（待建）
    ├── etc/              # nginx.conf、my.cnf、systemd unit（待建）
    ├── logs/             # nginx、mysql、spendge 日志（待建）
    └── backup/           # 数据库备份（已建；暂放项目备份/配置）

## 4. 端口规划

| 服务 | 监听 | 对外 | 阶段 |
|---|---|---|---|
| nginx | 8080 / 8443 | 是 | 测试期 |
| nginx | 80 / 443 | 是 | 备案后 |
| gunicorn | 127.0.0.1:8000 | 否 | 全程 |
| MySQL | 127.0.0.1:3306 | 否 | 全程 |

## 5. 技术选型与版本

| 组件 | 选型 |
|---|---|
| nginx | 最新 stable，源码编译到 local/nginx |
| MySQL | 8.0.x 官方二进制 tarball（glibc2.28），装到 local/mysql |
| 应用服务器 | gunicorn 2 worker，127.0.0.1:8000 |
| Python | 系统 python3 + venv |
| 进程管理 | systemd（nginx / mysqld / spendge 三个 unit） |
| HTTPS | 腾讯云免费证书（Nginx 格式） |

nginx 编译参数（关键模块）：

    ./configure --prefix=/home/ubuntu/local/nginx \
      --with-http_ssl_module --with-http_v2_module \
      --with-http_realip_module --with-http_gzip_static_module \
      --with-threads

## 6. 部署阶段

### 阶段 0 · 准备
- 创建 data/ etc/ logs/{nginx,mysql,spendge}。
- 安装依赖：build-essential libpcre2-dev zlib1g-dev libssl-dev libaio1t64 python3-venv。
- 腾讯云安全组放行 22、8080、8443（备案后加 80、443）。
- 复核 DNS：www.orokio.com 仅指向 124.223.27.87。
- 确认 9000 端口进程身份。

验收：目录齐备、依赖可装、安全组已开。

### 阶段 1 · nginx 源码编译安装
- 下载 stable tar 到 package/ 并解压编译（见上参数）。
- make && make install 到 local/nginx。
- 配置置于 etc/nginx/，日志指向 logs/nginx。
- 编写 systemd unit，enable 开机自启。

验收：nginx -t 通过；curl -I localhost:8080 返回 200。

### 阶段 2 · MySQL 8.0 二进制安装
- 下载 mysql-8.0.x-linux-glibc2.28-x86_64.tar.xz 到 package/，解压到 local/mysql。
- etc/my.cnf：basedir、datadir=data/mysql、bind-address=127.0.0.1、innodb_buffer_pool_size=256M、utf8mb4、socket 与日志路径。
- mysqld --initialize 初始化，妥善保存临时 root 密码。
- 编写 mysqld.service，enable；执行安全初始化。
- 建库 spendge（utf8mb4），建应用账号（仅 localhost、最小权限）。

验收：本地连接成功，SELECT 1 正常，应用账号可访问 spendge 库。

### 阶段 3 · Flask 应用
- 依据 server/pyproject.toml、.env.example、serve.sh 确定依赖与启动方式。
- 建 venv 安装依赖；按 .env.example 生成 .env（数据库连接、密钥等；密钥不入库、不入 git）。
- gunicorn --workers 2 --bind 127.0.0.1:8000 启动，编写 spendge.service。
- 运行 server/tests 校验。

验收：curl 127.0.0.1:8000/health 正常。

### 阶段 4 · nginx 反代 + HTTPS（测试端口）
- server 块：server_name www.orokio.com；proxy_pass http://127.0.0.1:8000；透传 Host / X-Real-IP / X-Forwarded-For / X-Forwarded-Proto。
- 证书放 local/nginx/conf/ssl/，先绑定 8443。
- 监听 8080（HTTP）、8443（HTTPS）。

验收：https://www.orokio.com:8443 命中应用，证书有效，真实 IP 透传。

### 阶段 5 · 全链路验证
- 8080/8443 访问、健康检查、核心接口冒烟、MySQL 读写、日志落盘。

### 阶段 6 · 备案后切正式端口
- nginx 改监听 80/443，加 80→443 跳转。
- 安全组放行 80/443。

验收：https://www.orokio.com 正常。

### 阶段 7 · 运维加固
- logrotate 轮转日志。
- crontab 定时 mysqldump 到 backup/。
- 三服务 enable 开机自启。
- 最小暴露面：3306/8000 不对外；关注内存与 OOM。

## 7. 验证清单
- [ ] nginx -t 通过，8080/8443 可访问
- [ ] MySQL 本地连接、应用账号可用
- [ ] gunicorn /health 正常
- [ ] HTTPS 证书生效、真实 IP 透传
- [ ] 三服务开机自启
- [ ] 备份任务可执行
- [ ] 备案后 80/443 正常

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| 内存紧张（1.9G） | MySQL buffer pool 256M、gunicorn 2 worker、保留 1.9G swap |
| 备案未完成 | 先用 8080/8443，80/443 后置 |
| Ubuntu 24.04 libaio 库名 | 安装 libaio1t64 |
| 源码 nginx 无系统服务 | 自写 systemd unit |
| DNS 残留旧 IP | 执行前复核仅保留本机 |
| 端口冲突 | 已规避 9000 等，执行前再确认 |

## 9. 回滚方案
- 单组件回退：停用对应 systemd 服务。
- 源码/二进制安装：删除 local/nginx、local/mysql 即干净卸载。
- 数据保护：变更前 mysqldump 至 backup/。

## 10. 待办确认（执行前）
- 依赖安装需 sudo 权限。
- 证书文件到位路径。
- 9000 端口进程身份确认。
