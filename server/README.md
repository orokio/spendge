# spendge-server

Spendge 的服务端，独立可部署单元。第一个真实用途是云端解析代理（鉴权、计量、转发模型），同步走 CloudKit，不经过这里。

> **状态（2026-11-24）**：未开工，v1 上架不依赖服务端；目前只有 Flask 骨架与 `/health`。开发与调试都在云机器上进行，本地不启动服务，只做读代码与语法检查。

## 边界

- 只依赖本目录：部署、依赖、环境变量都在 `server/` 内自洽
- 不引用 iOS 工程的任何代码，也不读写 `spendge/` 与 `spendge.xcodeproj`
- 密钥只走部署环境变量；仓库里只有 `.env.example`，`.env` 不入库
- 需要拆成独立仓库时，把整个目录搬走即可

## 本地运行

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env
flask --app app.main run --debug --port 9010
```

打开 http://127.0.0.1:9010/health 应返回 `{"status":"ok","env":"development"}`。

默认用 9010：8010 留给服务器上的生产 gunicorn（nginx upstream 固定指向它），dev 用 9010 避免冲突。

## 测试

```bash
pytest
```

## 起停

```bash
./serve.sh start          # 后台启动，默认 9010
./serve.sh status         # pid、端口、health
./serve.sh stop
./serve.sh restart
./serve.sh start --port 9011   # 换端口
```

日志和 pid 文件都在 `server/.run/`，不入库。脚本会先检查端口占用，启动后轮询 `/health` 确认真的起来了，失败时打印日志尾部。

## 部署（腾讯云）

部署形态还没定，代码先保持形态无关。已知两条路线，确定后再补具体步骤：

1. **SCF 云函数（Python 运行时）**：上传代码包，依赖随包或分层安装，入口按 WSGI 适配
2. **轻量应用服务器 / CVM**：venv 装依赖，gunicorn + systemd 常驻，nginx 反向代理到本机端口

nginx 在前面的三个必调项：

- `proxy_read_timeout` 放大到 60–120 秒，不然模型没返回就 504
- `client_max_body_size` 调大（截图解析会传图片，默认 1M 不够）
- 流式返回时关掉 `proxy_buffering`，并加 `X-Accel-Buffering: no`

对外只需要 HTTPS；证书、WAF / 基础防护由腾讯云侧承担。域名与备案在发布阶段处理，与代码无关。

## 约定

- 对外接口用 Blueprint 分组，在 `create_app()` 里注册；不要再建第二个 Flask 实例
- 配置只在 `app/config.py` 读取环境变量，别处不直接 `os.getenv`
- 请求日志不打印用户原文与金额，解析请求默认不留存
