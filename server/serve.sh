#!/usr/bin/env bash
# server/serve.sh — 本地起停服务
#
# 用法:
#   ./serve.sh status              查看状态与健康检查
#   ./serve.sh start [--port 8010] 启动
#   ./serve.sh stop                停止
#   ./serve.sh restart [--port 8010] 重启
#
# 日志与 pid 都在 server/.run/ 下，不入库。

set -euo pipefail
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SERVER_DIR/.venv"
RUN_DIR="$SERVER_DIR/.run"
PID_FILE="$RUN_DIR/server.pid"
LOG_FILE="$RUN_DIR/server.log"
PORT="${PORT:-8010}"

RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                PORT="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
}

require_venv() {
    if [[ ! -x "$VENV/bin/flask" ]]; then
        echo -e "${RED}✗ 找不到 ${VENV}/bin/flask${NC}"
        echo "  先装依赖：cd server && python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'"
        exit 1
    fi
}

pid() {
    [[ -f "$PID_FILE" ]] && cat "$PID_FILE" 2>/dev/null || true
}

is_running() {
    local pid; pid=$(pid)
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

port_in_use() {
    lsof -i :"$PORT" 2>/dev/null | grep -q LISTEN
}

health_ok() {
    curl -sf -m 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1
}

# ── 状态 ────────────────────────────────────────────────
cmd_status() {
    echo -e "${BLUE}=== spendge-server ===${NC}"
    if is_running; then
        local status="?"
        health_ok && status="ok"
        echo -e "  ${GREEN}● 运行中 (PID $(pid), 端口 $PORT, health=$status)${NC}"
        echo -e "  日志: ${LOG_FILE}"
    else
        if [[ -f "$PID_FILE" ]]; then
            echo -e "  ${YELLOW}○ 未运行（pid 文件已失效）${NC}"
        else
            echo -e "  ${RED}○ 未运行${NC}"
        fi
    fi
}

# ── 启动 ────────────────────────────────────────────────
cmd_start() {
    require_venv

    if is_running; then
        echo -e "  ${YELLOW}↻ 已在运行 (PID $(pid), 端口 $PORT)${NC}"
        return 0
    fi

    if port_in_use; then
        echo -e "  ${RED}✗ 端口 $PORT 已被占用${NC}"
        lsof -i :"$PORT" | head -5
        return 1
    fi

    mkdir -p "$RUN_DIR"
    cd "$SERVER_DIR"
    nohup "$VENV/bin/flask" --app app.main run --host 127.0.0.1 --port "$PORT" \
        >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if health_ok; then
            echo -e "  ${GREEN}✓ 已启动 (PID $(pid), 端口 $PORT)${NC}"
            echo -e "  health: http://127.0.0.1:$PORT/health"
            return 0
        fi
        sleep 0.3
    done

    echo -e "  ${RED}✗ 启动失败，最后几行日志：${NC}"
    tail -n 20 "$LOG_FILE" || true
    return 1
}

# ── 停止 ────────────────────────────────────────────────
cmd_stop() {
    if ! is_running; then
        rm -f "$PID_FILE"
        echo -e "  ${BLUE}⏵ 未在运行${NC}"
        return 0
    fi

    local pid; pid=$(pid)
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.3
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        echo -e "  ${YELLOW}✓ 已强制停止 (PID $pid)${NC}"
    else
        echo -e "  ${GREEN}✓ 已停止 (PID $pid)${NC}"
    fi
    rm -f "$PID_FILE"
}

# ── 主 ──────────────────────────────────────────────────
main() {
    local action="${1:-status}"
    shift || true
    parse_args "$@"

    case "$action" in
        status|-s) cmd_status ;;
        start)     cmd_start ;;
        stop)      cmd_stop ;;
        restart)
            cmd_stop
            sleep 0.5
            cmd_start
            ;;
        --help|-h)
            sed -n '2,10p' "$0"
            ;;
        *)
            echo "用法: $0 {status|start|stop|restart} [--port <port>]"
            exit 1
            ;;
    esac
}

main "$@"
