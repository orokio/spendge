# spendge-server

Spendge 的服务端，独立可部署单元。第一个真实用途是云端解析代理（鉴权、计量、转发模型），同步走 CloudKit，不经过这里。

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
uvicorn app.main:app --reload
```

打开 http://127.0.0.1:8000/health 应返回 `{"status":"ok"}`。

## 测试

```bash
pytest
```

## 部署（腾讯云）

部署形态还没定，代码先保持形态无关。已知两条路线，确定后再补具体步骤：

1. **SCF 云函数（Python 运行时）**：上传代码包，依赖随包或分层安装，入口按 ASGI 适配
2. **轻量应用服务器 / CVM**：venv 装依赖，uvicorn + systemd 常驻

对外只需要 HTTPS；证书、WAF / 基础防护由腾讯云侧承担。域名与备案在发布阶段处理，与代码无关。

## 约定

- 所有对外接口在 `app/main.py` 挂载，分组用 `APIRouter`
- 配置只在 `app/config.py` 读取环境变量，别处不直接 `os.getenv`
- 请求日志不打印用户原文与金额，解析请求默认不留存
