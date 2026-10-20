#!/usr/bin/env bash
# 启动浏览器实验室（若未运行）：.browserlab/www 静态服务
# 用法: ./scripts/lab_up.sh   环境变量 LAB_PORT 可改端口（默认 8931）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${LAB_PORT:-8931}"

if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
  echo "lab already up: http://127.0.0.1:$PORT/"
  exit 0
fi
cd "$ROOT"
nohup python "$ROOT/scripts/lab_server.py" >/dev/null 2>&1 &
sleep 2
CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT/")
if [ "$CODE" = "200" ]; then
  echo "lab up: http://127.0.0.1:$PORT/"
else
  echo "ERROR: lab failed to start (code $CODE)"
  exit 1
fi
