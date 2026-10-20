#!/usr/bin/env bash
# D1 冒烟：启动应用 -> 等待 -> 截图 -> OCR 判定关键词 -> 通过/失败报告
# 用法: ./scripts/smoke.sh [关键词...]   不传关键词时默认宽松判定（只要求进程活着+画面非空）
# 退出码: 0=PASS 1=FAIL
set -e
HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.readest.app"
ABILITY="EntryAbility"
WAIT="${SMOKE_WAIT:-8}"   # 首启含解包，可 SMOKE_WAIT=25 放宽

# --- 冷启动 ---
"$HDC" shell aa force-stop "$BUNDLE" >/dev/null 2>&1 || true
sleep 1
"$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE" >/dev/null
sleep "$WAIT"

# --- 进程存活判定（崩溃的硬信号）---
PID=$("$HDC" shell "pidof $BUNDLE" 2>/dev/null | tr -d '\r' | tr -d ' ')
if [ -z "$PID" ]; then
  echo "SMOKE: FAIL (process not alive after ${WAIT}s — crash or failed launch)"
  exit 1
fi

# --- 截图 + OCR ---
TEXT=$("$ROOT/scripts/observe.sh" "smoke" 2>/dev/null || true)
WORDS=$(echo "$TEXT" | tr -d ' \r' | wc -c)

# --- 关键词判定（OCR 会在 CJK 字符间插空格，匹配前统一剥离）---
declare -a KWS=("$@")
if [ ${#KWS[@]} -eq 0 ]; then
  if [ "$WORDS" -lt 4 ]; then
    echo "SMOKE: FAIL (alive pid=$PID but screen looks blank, ocr=${WORDS} chars)"
    echo "$TEXT"
    exit 1
  fi
  echo "SMOKE: PASS (alive pid=$PID, screen has text)"
  echo "$TEXT"
  exit 0
fi
CLEAN=$(echo "$TEXT" | tr -d ' \r')
MISSING=""
for kw in "${KWS[@]}"; do
  echo "$CLEAN" | grep -q "$(echo "$kw" | tr -d ' ')" || MISSING="$MISSING '$kw'"
done
if [ -n "$MISSING" ]; then
  echo "SMOKE: FAIL (alive pid=$PID, missing:$MISSING)"
  echo "$TEXT"
  exit 1
fi
echo "SMOKE: PASS (alive pid=$PID, all keywords found)"
echo "$TEXT"
exit 0
