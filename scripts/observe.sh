#!/usr/bin/env bash
# 观测闭环入口：截屏 -> 拉回本地 -> OCR 读屏
# 用法: ./scripts/observe.sh [名字]   产物在 .shots/<名字>.jpeg，OCR 文本打到 stdout
set -e
HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHOT_DIR="$ROOT/.shots"
mkdir -p "$SHOT_DIR"
NAME="${1:-screen_$(date +%H%M%S)}"

"$HDC" shell snapshot_display -f /data/local/tmp/screen.jpeg
"$HDC" file recv /data/local/tmp/screen.jpeg "$SHOT_DIR/$NAME.jpeg" >/dev/null
echo "---- OCR[$NAME] ----"
powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ROOT/scripts/ocr.ps1")" -Image "$(cygpath -w "$SHOT_DIR/$NAME.jpeg")"
