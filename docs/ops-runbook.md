# 运维手册（ops runbook）

> 适用主机：腾讯云 Ubuntu 24.04（124.223.27.87）｜ 最后更新：2026-11-26
> 本文只讲**日常运维命令**；装机与重建见 [deploy-plan.md](deploy-plan.md) §13，接口契约见 [api-contract.md](api-contract.md)。

## 1. 现状速查

    nginx 1.28.0 (源码)  0.0.0.0:8080 / 8443     systemd: nginx
    gunicorn 27.0.1      127.0.0.1:8010           systemd: spendge
    writer (write-behind) 无端口                  systemd: spendge-writer
    redis 7.0.15         127.0.0.1:6379           systemd: redis-server
    SQLite 3.45.1        /home/ubuntu/sqlite/spendge.db（WAL，无进程无端口）

| 项 | 路径 |
|---|---|
| 对外接口 | `https://api.orokio.com:8443/spendge/v1/...`（nginx 剥掉 `/spendge`） |
| 健康检查 | `https://www.orokio.com:8443/health`、`https://api.orokio.com:8443/spendge/health` |
| 源码（git） | `/home/ubuntu/spendge`（sparse-checkout：server/ docs/），**日常开发就在这里的 `server/`** |
| 开发服务器 | `127.0.0.1:9010`（`server/serve.sh` 默认端口；8010 留给生产 gunicorn） |
| 运行副本 | `/home/ubuntu/spendge-server`（代码 + .venv + .env + logs/ + run/） |
| nginx | `/home/ubuntu/nginx`（conf/ logs/ ssl/ sbin/） |
| 数据库 | `/home/ubuntu/sqlite/spendge.db`，备份目录 `/home/ubuntu/sqlite/backup/` |
| Redis | `/home/ubuntu/redis`（数据 + 日志） |
| unit 源文件 | `server/deploy/*.service` 与运行副本内同名文件，软链到 `/etc/systemd/system/` |

## 2. 日常检查（一条命令）

    for s in nginx spendge spendge-writer redis-server; do printf '%-16s %s / %s\n' "$s" "$(systemctl is-active $s)" "$(systemctl is-enabled $s)"; done
    curl -s -m 5 https://www.orokio.com:8443/health; echo
    curl -s -m 5 https://api.orokio.com:8443/spendge/health; echo
    df -h / | tail -1; free -h | sed -n '2p'
    ss -tln | awk 'NR>1{print $4}' | grep -E ':(8080|8443|8010|6379)$'

预期：4 个服务 `active / enabled`；两个 health 返回 `{"status":"ok"}`。

## 3. 服务启停

    sudo systemctl status nginx spendge spendge-writer redis-server
    sudo systemctl restart spendge            # 后端（改代码/配置后）
    sudo systemctl restart spendge-writer     # 落库进程
    sudo systemctl reload nginx               # 改 nginx.conf 后（不中断连接）
    sudo systemctl restart redis-server       # 慎用：清空限流计数与写队列前先确认已落库

    sudo systemctl stop spendge spendge-writer   # 维护窗口
    sudo systemctl start spendge-writer spendge  # 恢复顺序：writer 先起，再起接口

> 启动顺序：redis → writer → spendge。三者的 unit 已带 `After=redis-server.service`，正常重启不必手工排序。

## 4. 日志

    sudo journalctl -u spendge -f              # gunicorn 访问/错误
    sudo journalctl -u spendge-writer -f       # write-behind 落库
    sudo journalctl -u spendge -n 200 --no-pager
    sudo journalctl -u spendge --since '-1 hour' | grep -iE 'error|traceback'
    sudo journalctl -u redis-server -n 50 --no-pager
    sudo tail -f /home/ubuntu/nginx/logs/access.log
    sudo tail -f /home/ubuntu/nginx/logs/error.log

常用排查：

    # 最近的接口状态码分布
    sudo awk '{print $9}' /home/ubuntu/nginx/logs/access.log | sort | uniq -c | sort -rn | head
    # 只看客户端真实请求（排除本机 curl）
    sudo grep -v '124.223.27.87' /home/ubuntu/nginx/logs/access.log | tail -20
    # 5xx / 4xx 明细
    sudo awk '$9 ~ /^[45]/ {print $4, $6, $7, $9}' /home/ubuntu/nginx/logs/access.log | tail -20

## 5. 开发与发布流程（就在这台机器上开发）

开发环境在这台机器上（Redis、SQLite、nginx 都与生产同构），不再回本地。

### 5.1 日常开发

    cd /home/ubuntu/spendge/server        # git 工作区，直接改
    ./serve.sh start                      # 开发服务器，默认 9010（8010 留给生产 gunicorn）
    ./serve.sh status
    ./serve.sh stop

    .venv/bin/pytest -q                   # 测试：Redis 走 DB 15，不污染生产

- 开发服务器读 `server/.env`（同一 SQLite、同一 Redis DB0），**调试写入会进生产库**；测试产生的 device 记录记得清掉。
- 需要完全隔离时，改 `server/.env` 的 `DATABASE_URL` / `REDIS_URL` 指向临时库。
- `serve.sh` 的 pid/日志在 `server/.run/`（已 gitignore）。

### 5.2 发布到运行副本

    cd /home/ubuntu/spendge
    git add -A server docs && git commit -m "..." && git push origin main   # 先入库，机器丢了才不丢代码

    rsync -a --exclude '.venv' --exclude '.env' --exclude '.run' \
      --exclude '__pycache__' --exclude '.pytest_cache' --exclude '.git' \
      server/ /home/ubuntu/spendge-server/

    cd /home/ubuntu/spendge-server
    set -a; . ./.env; set +a
    .venv/bin/pip install -q .        # 仅依赖变化时需要
    .venv/bin/alembic upgrade head    # 有迁移时
    sudo systemctl restart spendge    # writer 只在 writer.py 变更时重启

    # 验收
    curl -s https://www.orokio.com:8443/health; echo
    curl -s -o /dev/null -w '%{http_code}\n' -X POST \
      https://api.orokio.com:8443/spendge/v1/devices/register \
      -H 'Content-Type: application/json' \
      -d '{"deviceId":"deploy-smoke","deviceSecret":"c2VjcmV0"}'

> 只改了 nginx.conf 时不需要 rsync，直接 `sudo /home/ubuntu/nginx/sbin/nginx -t && sudo systemctl reload nginx`。

## 6. 数据库（SQLite）

库文件：`/home/ubuntu/sqlite/spendge.db`（另有 `-wal`、`-shm`）。

    # 常用查询
    sqlite3 /home/ubuntu/sqlite/spendge.db ".tables"
    sqlite3 /home/ubuntu/sqlite/spendge.db "SELECT version_num FROM alembic_version;"
    sqlite3 -header -column /home/ubuntu/sqlite/spendge.db \
      "SELECT id, app_version, build, platform, last_seen_at FROM devices ORDER BY last_seen_at DESC LIMIT 10;"
    sqlite3 -header -column /home/ubuntu/sqlite/spendge.db \
      "SELECT value FROM app_config WHERE key='categories_version';"
    sqlite3 /home/ubuntu/sqlite/spendge.db "PRAGMA journal_mode;"      # 应为 wal

    # 备份（唯一正确方式，写入过程中也一致）
    sqlite3 /home/ubuntu/sqlite/spendge.db \
      ".backup /home/ubuntu/sqlite/backup/spendge-$(date +%F).db"

    # 手工恢复（先停写：接口与 writer 都停）
    sudo systemctl stop spendge spendge-writer
    cp /home/ubuntu/sqlite/spendge.db /home/ubuntu/sqlite/spendge.db.bad
    rm -f /home/ubuntu/sqlite/spendge.db-wal /home/ubuntu/sqlite/spendge.db-shm
    cp /home/ubuntu/sqlite/backup/spendge-2026-11-26.db /home/ubuntu/sqlite/spendge.db
    sudo systemctl start spendge-writer spendge

**禁止**直接 `cp` 正在使用的库文件（会得到不一致的页）；必须用 `.backup` 或 `VACUUM INTO`。

## 7. Redis

密码不入库到文档；从配置读：

    PW=$(sudo grep '^requirepass ' /etc/redis/redis.conf | awk '{print $2}' | head -1)
    REDISCLI_AUTH=$PW redis-cli ping
    REDISCLI_AUTH=$PW redis-cli info memory | grep -E 'used_memory_human|maxmemory_human'
    REDISCLI_AUTH=$PW redis-cli info persistence | grep -E 'aof_enabled|aof_current_size|aof_last_write_status'
    REDISCLI_AUTH=$PW redis-cli dbsize
    REDISCLI_AUTH=$PW redis-cli keys 'device:*' | head        # 读模型缓存
    REDISCLI_AUTH=$PW redis-cli keys 'rl:*' | head            # 限流计数（TTL 60s）
    REDISCLI_AUTH=$PW redis-cli xlen stream:register           # 待落库队列长度
    REDISCLI_AUTH=$PW redis-cli xinfo groups stream:register   # 消费组滞后（lag 应接近 0）

- 限流键 `rl:ip:*` / `rl:dev:*` 是**固定窗口计数**，调接口前别猛刷。
- AOF 已开（`appendonly yes`、`appendfsync everysec`），写队列落库前不丢。
- 清限流（仅调试）：`REDISCLI_AUTH=$PW redis-cli --scan --pattern 'rl:*' | xargs -r redis-cli del`。
- Redis 挂掉时 `/v1/devices/register` 直接 **503**（不回退同步写 DB），先恢复 Redis。

## 8. 分类数据（categories）

    cd /home/ubuntu/spendge-server
    set -a; . ./.env; set +a

    .venv/bin/python -m app.categories /home/ubuntu/spendge/docs/categories-seed.json  # 导入/更新（幂等）
    .venv/bin/python -m app.categories --versions    # 历史版本
    .venv/bin/python -m app.categories --show 4      # 查看某版全量
    .venv/bin/python -m app.categories --restore 3   # 回放到某版（版本仍 +1）

- 任何展示字段（name/iconName/colorHex/sortOrder/isArchived/goalKinds）变化 → `categoriesVersion +1` 并失效 Redis 快照。
- 版本只增不减；改错就再改一次，不要手工改小。
- 导入后客户端下次 register 自动拉全量（凭 `categoriesVersion`）。

## 9. HTTPS 证书

| 域名 | 证书文件 | 到期 |
|---|---|---|
| api.orokio.com（接口） | `/home/ubuntu/nginx/conf/ssl/api.orokio.com_nginx/api.orokio.com_nginx/api.orokio.com_bundle.pem` | 2027-02-23 |
| orokio.com / www（保留） | `/home/ubuntu/nginx/conf/ssl/orokio.com_nginx/orokio.com_bundle.pem` | 2027-02-20 |

腾讯云免费证书 3 个月，到期前重新申请（Nginx 格式 zip）→ 解压覆盖上述目录 → 校验 → reload：

    openssl x509 -in <bundle.pem> -noout -subject -dates -ext subjectAltName
    sudo /home/ubuntu/nginx/sbin/nginx -t && sudo systemctl reload nginx
    echo | openssl s_client -connect 127.0.0.1:8443 -servername api.orokio.com 2>/dev/null | openssl x509 -noout -dates

## 10. nginx

    sudo /home/ubuntu/nginx/sbin/nginx -t     # 必须以 root 执行（pid 文件属 root）
    sudo systemctl reload nginx
    sudo systemctl restart nginx

- 配置：`/home/ubuntu/nginx/conf/nginx.conf`（日志到 `logs/`）。
- 路由：`api` 域只保留 `location /spendge/` → `proxy_pass .../ `（剥前缀），根路径 404；`www` 域根路径保留给探活/旧包。
- 安全组需放行 TCP 8080、8443（备案后再放 80/443）。

## 11. 常见故障处置

| 现象 | 先查 | 处置 |
|---|---|---|
| 502 Bad Gateway | `systemctl status spendge`、`journalctl -u spendge -n 50` | 后端挂了/端口不对；重启 spendge |
| 504 超时 | nginx `proxy_read_timeout`、gunicorn `--timeout` | 已有 120s / 90s，确认不是慢查询 |
| 503 `service_unavailable` | `redis-cli ping`、`journalctl -u spendge` | Redis 不可用；恢复 redis-server |
| 429 `rate_limited` | `keys 'rl:*'` | 正常限流（IP 10/分、deviceId 5/分）；调试可清键 |
| 登记成功但库里没数据 | `xlen stream:register`、`journalctl -u spendge-writer` | writer 未运行/报错；起 writer，lag 会补 |
| 403 `secret_mismatch` | 客户端是否换了 deviceSecret | 客户端必须沿用首次生成的 secret |
| api 域根路径 404 | 预期行为 | 客户端走 `/spendge/...` |
| Redis 启动失败 | `journalctl -u redis-server` | `/home/ubuntu` 需 `o+x`；unit 有 `ProtectHome=false` + `ReadWritePaths=/home/ubuntu/redis` |
| nginx -t 报 pid 权限 | — | 用 sudo 执行 |
| 内存吃紧 / OOM | `free -h`、`systemd-cgtop -m` | 服务栈约 220M；`MemoryMax` 700M/200M；必要时扩到 4G |

## 12. 监控阈值

| 指标 | 警戒 | 动作 |
|---|---|---|
| 内存 available | < 200M 或持续 swap > 300M | 查大户、考虑升 4G |
| 磁盘 | > 80% | 清日志/备份，扩盘 |
| writer lag（`xinfo groups`） | 持续 > 1000 | 查 writer 日志与 SQLite 锁 |
| 5xx 比例 | > 1% 持续 5 分钟 | 查 gunicorn/Redis |
| AOF 大小 | 异常增长 | 查写入量、`bgrewriteaof` |

## 13. 自动化任务（已配置）

### 13.1 每日 SQLite 备份

- 脚本：`/home/ubuntu/sqlite/backup.sh`（`.backup` → 完整性自检 → gzip → 清理 30 天前）
- 定时：ubuntu 用户 crontab，`30 3 * * *`（每天 03:30 CST）
- 产物：`/home/ubuntu/sqlite/backup/spendge-YYYY-MM-DD.db.gz`
- 日志：`/home/ubuntu/sqlite/backup/backup.log`

      crontab -l                                    # 查看
      bash /home/ubuntu/sqlite/backup.sh            # 手工跑一次
      tail -5 /home/ubuntu/sqlite/backup/backup.log # 看最近结果
      ls -lh /home/ubuntu/sqlite/backup/            # 现有备份

恢复见 §6（先停 spendge + spendge-writer，删掉 `-wal/-shm` 再覆盖）。

### 13.2 nginx 日志轮转

- 配置：`/etc/logrotate.d/spendge-nginx`
- 由 `logrotate.timer` 每天 00:00 触发；每日轮转、保留 14 份、`dateext`、gzip（当天文件 delaycompress）
- 轮转后向 nginx 发 `USR1` 重新打开日志；新文件 `0640 ubuntu:ubuntu`
- **日志目录必须 755**：`/home/ubuntu/nginx/logs` 若被改成组可写，logrotate 会以 "insecure permissions" 跳过

      sudo logrotate -d /etc/logrotate.d/spendge-nginx   # 干跑
      sudo logrotate -f /etc/logrotate.d/spendge-nginx   # 立即轮转（当天已轮转过会提示 destination exists）
      ls -lh /home/ubuntu/nginx/logs/

> journald（gunicorn / writer）目前未限容量，可按需加 `SystemMaxUse=200M`。

### 13.3 仍待办

- **备案后切 80/443**：改 nginx listen + 80→443 跳转，安全组放行 80/443。
- **证书续期**：api 至 2027-02-23、www 至 2027-02-20，到期前重新申请并替换（§9）。
## 14. 手工操作（应急 / 排障）

> 前缀统一先取一次密码：`export REDISCLI_AUTH=$(sudo grep '^requirepass ' /etc/redis/redis.conf | awk '{print $2}' | head -1)`，下文 redis-cli 都可直接用。

### 14.1 只同步代码到运行副本

    rsync -a --exclude '.venv' --exclude '.env' --exclude '.run' \
      --exclude '__pycache__' --exclude '.pytest_cache' --exclude '.git' \
      /home/ubuntu/spendge/server/ /home/ubuntu/spendge-server/
    sudo systemctl restart spendge

完整发布（含 pull / 依赖 / 迁移）见 §5。

### 14.2 手动刷一次落库

把 `stream:register` 里未消费的消息写进 SQLite（等价于 writer 跑一轮）：

    cd /home/ubuntu/spendge-server && set -a; . ./.env; set +a
    .venv/bin/python -c "from app.writer import process_batch; print('processed =', process_batch(batch=1000, block_ms=200))"

- 与运行中的 `spendge-writer` 并发安全（消费组保证一条消息只投给一个消费者）
- 队列为空返回 `processed = 0`
- 先看积压：`redis-cli xlen stream:register`、`redis-cli xinfo groups stream:register`（`lag` 应接近 0）

### 14.3 Redis 读模型（device:*）

    redis-cli --scan --pattern 'device:*' | head
    redis-cli get "device:<deviceId>" | python3 -m json.tool
    redis-cli del "device:<deviceId>"      # 只删缓存；下次 register 只读回源 DB
    redis-cli --scan --pattern 'rl:*' | xargs -r redis-cli del   # 清限流计数（仅调试）

**不要手工 `SET device:<id>`**：读模型字段与 DB 状态需一致，写错会造成缓存与库漂移；排障时删掉让它回源即可（cache-aside，不写库）。

### 14.4 写队列（stream:register）

    redis-cli xlen stream:register
    redis-cli xinfo groups stream:register
    redis-cli xinfo consumers stream:register writer
    redis-cli xtrim stream:register MAXLEN ~ 10000     # 一般不需要，应用已带近似裁剪

- 应用侧 `XADD` 已带 `maxlen=10000, approximate`，流不会无限增长。
- `xgroup destroy` 只用于清理测试遗留组，生产只有一个 `writer` 组。

### 14.5 SQLite 手工改数据（安全流程）

    sudo systemctl stop spendge spendge-writer
    sqlite3 /home/ubuntu/sqlite/spendge.db \
      ".backup /home/ubuntu/sqlite/backup/pre-manual-$(date +%F-%H%M).db"
    sqlite3 /home/ubuntu/sqlite/spendge.db "UPDATE ... WHERE ...;"
    sqlite3 /home/ubuntu/sqlite/spendge.db "PRAGMA integrity_check;"
    sudo systemctl start spendge-writer spendge

- 必须先停 `spendge-writer`，否则 writer 的 upsert 会覆盖你的修改或触发锁等待。
- 分类数据**不要用 UPDATE**：改 `docs/categories-seed.json` 后走 §8 导入（自动 +1 版本并失效缓存）。

### 14.6 未 ack 的消息（writer 崩溃后）

writer 在批处理异常时不会 ack，消息留在 PEL 里；当前没有自动 `XAUTOCLAIM`，需要人工确认后再补：

    redis-cli xpending stream:register writer
    redis-cli xack stream:register writer <消息ID>    # 确认已落库（或已手工补写）后再 ack

先核对对应 device 是否已在库里，避免盲目 ack 丢登记。
## 15. 用户统计（T-1）

每天 00:10 算昨天（东八区），只输出一个文件，**覆盖写**：

    /home/ubuntu/stats/latest.txt

    cd /home/ubuntu/spendge-server && set -a; . ./.env; set +a
    .venv/bin/python -m app.stats                     # 昨天
    .venv/bin/python -m app.stats --date 2026-11-25   # 补算某天（覆盖同一文件）
    cat /home/ubuntu/stats/latest.txt

文件内容示例：

    统计日期: 2026-11-25（东八区）
    生成时间: 2026-11-26 00:10（东八区）

    新增: 13
    活跃: 10

    build    新增   活跃
    2           6      6
    3           2      2

- 新增：`devices.created_at` 落在当天（东八区）
- 活跃：当天至少一次成功 register；口径 = `device_daily` ∪ 当天 `created_at`，因此**新增一定包含在活跃里**
- 合法设备：36 位大写 UUID 且 `secret_hash` 非空
- 定时：crontab `10 0 * * *`，日志 `spendge-server/logs/stats.log`
- 只有 `device_daily` 一张明细表；`user_stats_daily` 已删除，不再保留历史汇总（文件每天覆盖）
