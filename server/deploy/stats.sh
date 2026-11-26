#!/usr/bin/env bash
# 手动生成用户统计（昨天 + 今天，东八区），结果写到 /home/ubuntu/stats/latest.txt
set -euo pipefail

APP_DIR=/home/ubuntu/spendge-server
OUT=/home/ubuntu/stats/latest.txt

cd "$APP_DIR"
set -a
. ./.env
set +a

.venv/bin/python -m app.stats
echo
cat "$OUT"
