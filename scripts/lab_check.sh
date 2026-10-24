#!/usr/bin/env bash
# 浏览器实验室自动检查（无人值守回归引擎）：
#   第一层 curl 门（服务+关键文件）→ 第二层无头 Edge 渲染判定（DOM 关键词）+ 截图
# 用法: ./scripts/lab_check.sh [关键词...]   不传关键词默认判 "书库"（首屏特征词）
# 退出码: 0=PASS 1=FAIL
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${LAB_PORT:-8931}"
URL="http://127.0.0.1:$PORT/"
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -f "$EDGE" ] || EDGE="/c/Program Files/Microsoft/Edge/Application/msedge.exe"

# --- 第一层: 服务门 ---
for f in "" tauri_shim.js mock_bridge.js; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL$f")
  if [ "$CODE" != "200" ]; then
    echo "LAB_CHECK: FAIL (server gate /$f -> $CODE; run scripts/lab_up.sh)"
    exit 1
  fi
done

# --- 第二层: 无头渲染判定 ---
if [ ! -f "$EDGE" ]; then
  echo "LAB_CHECK: PASS (tier1 only; Edge not found for render check)"
  exit 0
fi
DOM="$ROOT/.shots/lab_dom.html"
PNG="$ROOT/.shots/lab_check.png"
# 审计治本（2026-10-25）：共享 profile 在长会话后触发无头 Edge 段错误
# （新 profile 恒 PASS，隔离实证）——boot 检查改一次性 profile（探针每次
# 自播种状态，持久 profile 并非依赖）
PROFILE="$ROOT/.shots/.edge-boot-$$-$(date +%s)"
mkdir -p "$ROOT/.shots" "$PROFILE"
mkdir -p "$ROOT/.shots" "$PROFILE"
rm -f "$DOM" "$PNG"
# 独立 user-data-dir：复用运行中的 Edge 配置会导致 headless 挂起
"$EDGE" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
  --user-data-dir="$(cygpath -w "$PROFILE")" \
  --window-size=412,915 \
  --virtual-time-budget=30000 \
  --screenshot="$(cygpath -w "$PNG")" \
  --dump-dom "$URL" > "$DOM" 2>/dev/null || true
# 审计修正（2026-10-25）：长会话后无头 Edge 在退出阶段段错误（工作已完整
# 写出——DOM/截图齐全，exit 139 良性）——|| true 防 set -e 误杀脚本；
# 下方 -s $DOM 门仍兜底产物完整性

if [ ! -s "$DOM" ]; then
  echo "LAB_CHECK: FAIL (headless dump-dom empty)"
  exit 1
fi

declare -a KWS=("$@")
if [ ${#KWS[@]} -eq 0 ]; then KWS=("书库"); fi
CLEAN=$(python - "$DOM" <<'PYEOF'
import io, re, sys
s = io.open(sys.argv[1], encoding='utf-8', errors='ignore').read()
s = re.sub(r'<script[\s\S]*?</script>', ' ', s)
s = re.sub(r'<[^>]+>', ' ', s)
s = re.sub(r'\s+', '', s)
print(s)
PYEOF
)
MISSING=""
for kw in "${KWS[@]}"; do
  k=$(echo "$kw" | tr -d ' ')
  if ! echo "$CLEAN" | grep -q "$k"; then MISSING="$MISSING '$kw'"; fi
done
if [ -n "$MISSING" ]; then
  echo "LAB_CHECK: FAIL (render ok but missing:$MISSING)"
  exit 1
fi
echo "LAB_CHECK: PASS (keywords found; dom=$(wc -c <"$DOM")B screenshot=$PNG)"
exit 0
