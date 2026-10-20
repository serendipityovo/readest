#!/usr/bin/env bash
# 回归套件 v2（D5）：启动 → 库渲染（书库+导入）→ 开书链（READER-PROBE：Repro+第1页）
# 结果追加 .shots/regression.log，退出码 0=PASS 1=FAIL
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.shots"

bash "$ROOT/scripts/lab_up.sh" >/dev/null

ST=PASS
OUT=$(timeout 90 bash "$ROOT/scripts/lab_check.sh" "书库" "导入" 2>&1) || ST=FAIL
echo "$OUT"

# tier-3: reader chain probe (seed fixture + /reader?ids -> markers in dump-dom)
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -f "$EDGE" ] || EDGE="/c/Program Files/Microsoft/Edge/Application/msedge.exe"
R3=""
if [ -f "$EDGE" ]; then
  R3=$("$EDGE" --headless=new --disable-gpu --no-first-run --no-default-browser-check \
    --user-data-dir="$(cygpath -w "$ROOT/.browserlab/.edge-profile")" \
    --window-size=412,915 --virtual-time-budget=60000 \
    --dump-dom "http://127.0.0.1:8931/probe_reader.html" 2>/dev/null | python -c "
import sys, re
s = sys.stdin.buffer.read().decode('utf-8', 'ignore')
s = re.sub(r'<script[\s\S]*?</script>', ' ', s)
s = re.sub(r'<style[\s\S]*?</style>', ' ', s)
s = re.sub(r'<[^>]+>', ' ', s)
s = re.sub(r'\s+', '', s)
ok = ('Repro' in s) and ('第1页' in s)
print('READER-PROBE ' + ('PASS' if ok else 'FAIL'))
" || echo 'READER-PROBE FAIL')
  echo "$R3"
  echo "$R3" | grep -q FAIL && ST=FAIL
fi

echo "$(date '+%F %T')  v2  $ST  | $OUT | $R3" >> "$ROOT/.shots/regression.log"
if [ "$ST" = "PASS" ]; then exit 0; else exit 1; fi
