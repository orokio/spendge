# 后端部署计划（spendge server）

> 状态：**进行中**（2026-11-24 更新）｜ v1 需最小部署以承载 `/v1/devices/register` ｜ 开发与调试都在云机器上进行，本地不做服务端开发 ｜ 适用主机：腾讯云 Ubuntu 24.04
> 本文是部署的唯一依据；架构与接口见 [server-design.md](server-design.md)。

## 1. 概述

为 spendge App 部署后端服务。代码位于 spendge/server（Flask），采用 nginx 反向代理 + gunicorn + SQLite + Redis 的单机架构；Redis 做限流、幂等与抗刷前置，挡在 DB 之前。基础软件采用"源码/二进制包放 package、安装到各自目录（如 nginx/）"的自管理方式，便于版本控制与后续容器化；SQLite、Redis 用系统包，不单独编译。

### 架构

    用户
       │ HTTP/HTTPS
       ▼
    nginx（反向代理）   测试 8080/8443 → 备案后 80/443
       │ proxy_pass 127.0.0.1:8010
       ▼
    gunicorn + Flask（2 worker × 4 线程）
       │
       ├── SQLite  /home/ubuntu/sqlite/spendge.db（WAL）
       └── Redis   127.0.0.1:6379（限流 / 幂等 / 抗刷，前置）

## 2. 环境基线

| 项 | 值 |
|---|---|
| 系统 | Ubuntu 24.04.4 LTS x86_64 |
| CPU | 2 vCPU |
| 内存 | 1.9G + swap 1.9G |
| 磁盘 | 50G（可用约 35G） |
| 公网 IP | 124.223.27.87 |
| 域名 | www.orokio.com（ICP 备案进行中） |
| 已装服务 | 无 nginx / 无 mysql / 无 redis |

已占用端口（需规避）：22、53、3080（node）、59087（node/CodeBuddy）。9000/9001/9003 的旧 python 服务已停止；8000/8010/8080/8443/6379 均空闲。

## 3. 目录规划

    /home/ubuntu/
    ├── spendge/          # git 代码仓库（server/、docs/）：开发与源头
    ├── package/          # 下载的源码/安装包
    ├── nginx/            # nginx 自包含（--prefix=这里）：conf/、logs/、ssl/
    ├── sqlite/           # 数据库自包含：spendge.db（含 -wal/-shm）、backup/
    └── spendge-server/   # 运行副本（从 git 同步）：app/、.venv/、.env、logs/、run/

> 组件按目录自包含（配置、日志、数据都在各自目录内，不设全局 etc/logs/data）；运行副本 spendge-server 与源码 spendge 分离，生产只从副本启动。

## 4. 端口规划

| 服务 | 监听 | 对外 | 阶段 |
|---|---|---|---|
| nginx | 8080 / 8443 | 是 | 测试期 |
| nginx | 80 / 443 | 是 | 备案后 |
| gunicorn | 127.0.0.1:8010 | 否 | 全程 |
| Redis | 127.0.0.1:6379 | 否 | 全程 |

> gunicorn 用 8010：与本地 serve.sh 默认端口一致（8000 经核实为空闲）。

## 5. 技术选型与版本

| 组件 | 选型 |
|---|---|
| nginx | 最新 stable，源码编译到 nginx/ |
| SQLite | 系统 sqlite3（apt），库文件放 sqlite/ |
| Redis | 系统 redis-server（apt，7.x），仅本机；限流 / 幂等 / 抗刷前置 |
| 应用服务器 | gunicorn 2 worker × 4 线程，127.0.0.1:8010（加入 pyproject 依赖） |
| Python | 系统 python3 + venv |
| 进程管理 | systemd（nginx / redis-server / spendge 三个 unit；SQLite 无服务） |
| HTTPS | 腾讯云免费证书（Nginx 格式） |

nginx 编译参数（关键模块）：

    ./configure --prefix=/home/ubuntu/nginx \
      --with-http_ssl_module --with-http_v2_module \
      --with-http_realip_module --with-http_gzip_static_module \
      --with-threads

## 6. 内存预算（1.9G）

| 组件 | 预计常驻 |
|---|---|
| 系统（Ubuntu 24.04） | 250–350M |
| nginx | 15M |
| gunicorn 2×4 | 180–220M |
| SQLite | 进程内，页缓存几十 MB |
| Redis（maxmemory 128M） | 60M |
| 合计 | 约 0.6–0.7G |

剩余给 page cache 与突发；swap 只做兜底。上表成立的前提是当前已用的约 1G 能查清并释放，否则先升 4G。

## 7. 部署阶段

### 阶段 0 · 准备
- 创建 nginx/、sqlite/ 与 sqlite/backup/、redis/；运行副本 spendge-server/ 在阶段 3 生成。
- 安装依赖：build-essential libpcre2-dev zlib1g-dev libssl-dev python3-venv sqlite3 redis-server。
- 腾讯云安全组放行 22、8080、8443（备案后加 80、443）；6379 与 8010 不对外。
- 复核 DNS：www.orokio.com 仅指向 124.223.27.87。
- 复核 8010/8080/8443/6379 在部署时仍空闲（8000/9000/9001/9003 已核实空闲）。

验收：目录齐备、依赖可装、安全组已开。

### 阶段 1 · nginx 源码编译安装
- 下载 stable tar 到 package/ 并解压编译（见上参数）。
- make && make install 到 /home/ubuntu/nginx。
- 配置在 nginx/conf/，日志在 nginx/logs/（自包含）。
- 编写 systemd unit，enable 开机自启。

验收：nginx -t 通过；curl -I localhost:8080 返回 200。

### 阶段 2 · SQLite 与 Redis 初始化

SQLite：

- 创建 sqlite/（属主 ubuntu，权限 750）与 sqlite/backup/。
- 库文件由应用首次启动时创建（Alembic 迁移）；不要手工建库/建表。
- WAL 等 PRAGMA 由应用连接时设置（见 server-design §6）；WAL 实际验证放到阶段 3 应用启动后。
- 每日备份：

      sqlite3 /home/ubuntu/sqlite/spendge.db \
        ".backup /home/ubuntu/sqlite/backup/spendge-$(date +%F).db"

- **禁止直接 cp 库文件**：写入过程中复制会得到不一致的页。

Redis（限流 / 幂等 / 抗刷，全部前置在 DB 之前）：

- 创建 redis/（数据与日志目录，自包含）。
- 修改 /etc/redis/redis.conf：

      bind 127.0.0.1
      protected-mode yes
      requirepass <随机长密码>
      maxmemory 128mb
      maxmemory-policy volatile-lru
      save ""
      appendonly no
      dir /home/ubuntu/redis
      logfile /home/ubuntu/redis/redis.log

- `systemctl enable --now redis-server`，用 `REDISCLI_AUTH=... redis-cli ping` 验证，避免密码进 history。
- 限流与幂等：按 IP / deviceId 滑动窗口计数（如 20 次/分/设备），重复请求用 SETNX 幂等键挡在前面，命中即返回、不落 DB。
- 所有键带 TTL；Redis 只存计数、幂等键与热点缓存，重启丢失不影响正确性（devices/usage 唯一键兜底）。
- Redis 不可用时：非核心路径降级放行，写操作回落到 DB（限流暂时失效但不阻断）。

验收：SQLite 目录就绪（WAL 待阶段 3 应用建库后验证）；Redis 返回 PONG；6379 不对公网。

### 阶段 3 · 运行副本 + Flask 应用
- 运行副本 spendge-server/：从 git 的 server/ 同步代码（rsync，排除 .venv/.env/.git/logs），与源码分离，生产只跑副本。
- 前置：v1 先实现 devices 表与 `/v1/devices/register`（SQLAlchemy + Alembic）；accounts/usage/diagnostics 等随 M4 再补。
- 在 spendge-server/ 建 venv 安装依赖（把 gunicorn 加入 pyproject 依赖）；按 .env.example 生成 .env（不入库、不入 git）。
- .env 关键项：

      DATABASE_URL=sqlite:////home/ubuntu/sqlite/spendge.db

- 建表：在 spendge-server/ 执行 `alembic upgrade head`。
- 启动：

      gunicorn -w 2 --threads 4 -b 127.0.0.1:8010 \
        --timeout 90 --max-requests 800 --max-requests-jitter 100 \
        app.main:app

- 编写 spendge.service（WorkingDirectory 指向 spendge-server，日志到 spendge-server/logs/），加 `MemoryMax=700M`，enable。
- 运行 tests 校验。

验收：curl 127.0.0.1:8010/health 正常；`/v1/devices/register` 可写入 devices 表；`sqlite3 /home/ubuntu/sqlite/spendge.db "PRAGMA journal_mode;"` 返回 `wal`。

### 阶段 4 · nginx 反代 + HTTPS（测试端口）
- server 块：server_name www.orokio.com；proxy_pass http://127.0.0.1:8010；透传 Host / X-Real-IP / X-Forwarded-For / X-Forwarded-Proto。
- 请求体上限：`client_max_body_size 4m;`（/v1/parse 接收 2MB 图片，nginx 默认 1m 会 413）。
- 上游超时：`proxy_read_timeout 120s;` 与 `proxy_send_timeout 120s;`（gunicorn --timeout 90，需大于它，避免解析慢时 504）。
- 证书放 nginx/conf/ssl/，先绑定 8443。
- 监听 8080（HTTP）、8443（HTTPS）。
- 预置限流：按 server-design §7 的起步参数配置 limit_req / limit_conn。

验收：https://www.orokio.com:8443 命中应用，证书有效，真实 IP 透传。

### 阶段 5 · 全链路验证
- 8080/8443 访问、健康检查、核心接口冒烟、SQLite 读写、Redis PING、日志落盘。
- 手动执行一次备份，并恢复到临时目录验证可用。

### 阶段 6 · 备案后切正式端口
- nginx 改监听 80/443，加 80→443 跳转。
- 安全组放行 80/443。

验收：https://www.orokio.com 正常。

### 阶段 7 · 运维加固
- logrotate 轮转 nginx/logs 与 spendge-server/logs；journald SystemMaxUse=200M。
- crontab 每日 SQLite 备份到 sqlite/backup/，并上传 COS 保留 30 天。
- nginx / redis-server / spendge 三个 unit enable 开机自启。
- 系统：`vm.swappiness=10`；最小暴露面：6379/8010 不对外。
- 关注内存与 OOM，配置告警。

## 8. 运行与升级触发

监控项：

- 内存 >85%、swap 占用 >300M、磁盘 >80%
- gunicorn 5xx 比例、解析 P95 延迟
- Redis 出现 evicted keys（volatile-lru 下不应影响业务键）

触发动作：

- **升到 4G**：swap 持续占用、出现 OOM kill、部署时接口明显抖动
- **迁到 MariaDB**：需要多实例部署、写事务排队明显、需要慢查询日志或主从（不使用 MySQL 8：比 MariaDB 多吃 100–150M）
- **Redis 故障**：非付费路径降级放行，付费与额度路径失败即拒绝

## 9. 验证清单
- [ ] nginx -t 通过，8080/8443 可访问
- [ ] SQLite 库为 WAL 模式，可读写
- [ ] `/v1/devices/register` 可写入且有唯一约束（重复上报只更新 last_seen）
- [ ] Redis 有密码、仅本机、maxmemory 与限流生效
- [ ] gunicorn /health 正常（8010）
- [ ] HTTPS 证书生效、真实 IP 透传
- [ ] 三服务（nginx / redis / spendge）开机自启
- [ ] 备份任务可执行，且恢复演练通过
- [ ] 备案后 80/443 正常

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| 内存紧张（1.9G） | SQLite 省掉数据库常驻；Redis maxmemory 128M；gunicorn 2×4；保留 1.9G swap |
| SQLite 单写者 | 写事务短、不跨模型调用；busy_timeout 5s；单机部署 |
| SQLite 备份不一致 | 只用 `.backup` / `VACUUM INTO`，禁止 cp |
| 备案未完成 | 先用 8080/8443，80/443 后置 |
| 源码 nginx 无系统服务 | 自写 systemd unit |
| DNS 残留旧 IP | 执行前复核仅保留本机 |
| 端口冲突 | 部署前核实 8010/8080/8443/6379 空闲（8000/9000 等已核实空闲） |
| 被刷接口 / 应用层攻击 | nginx limit_req/limit_conn + 腾讯云 WAF；Redis 幂等键前置挡重复；App Attest 校验；DB 唯一键兜底 |

## 11. 回滚方案
- 单组件回退：停用对应 systemd 服务。
- 源码安装：删除 nginx/ 即干净卸载；运行副本删除 spendge-server/ 即可；Redis 用 apt 卸载并清配置。
- 数据保护：变更前执行 SQLite 备份；回滚时用备份覆盖库文件，WAL 旁文件一并处理。

## 12. 待办确认（执行前）
- **v1 需部署最小服务**：承载 `/v1/devices/register`（nginx + gunicorn + SQLite devices 表）；解析/诊断随 M4 再扩。
- 域名与 ICP 备案、HTTPS 证书（含续期方式）。
- 腾讯云实例规格与预算复核（内存 1.9G 是否仍适用）。
- 模型供应商、调用预算与限流策略（决定是否需要 Redis 计数）。
- 依赖安装需 sudo 权限。
- 证书文件到位路径。
- 部署前复核 8010/8080/8443/6379 仍空闲。
- 生成 Redis 密码并写入 .env 与 redis.conf（不入库）。
- 实现 devices 表 + `/v1/devices/register`（SQLAlchemy + Alembic）后，方可完成阶段 2/3 的接口验证。
- 当前已用的约 1G 内存归属查清。