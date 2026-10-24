#!/usr/bin/env bash
# 回归套件 v3（D10 总预演）：串联全部探针——
#   boot（书库+导入）/ reader（开书）/ turso（DB 链）/ tts（持续朗读）/
#   http（真网 fetch）/ opds（下载入库，真网 best-effort）/ opds_fail（失败路径）
# 每项独立 headless Edge 会话；结果追加 .shots/regression.log，退出码 0=PASS
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.shots"

bash "$ROOT/scripts/lab_up.sh" >/dev/null

EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
[ -f "$EDGE" ] || EDGE="/c/Program Files/Microsoft/Edge/Application/msedge.exe"

if [ ! -f "$EDGE" ]; then
  echo "ERROR: Edge not found"; exit 1
fi

# 审计治本（2026-10-25）：一次性 profile（共享 profile 触发 Edge 段错误，
# 隔离实证；探针每次自播种，无持久依赖）
PROFILE="$(cygpath -w "$ROOT/.shots/.edge-v3-$$-$(date +%s)")"
RESULTS=""

record() { # $1=name $2=PASS/FAIL
  RESULTS+="[$1:$2]"
  echo "$1 $2"
}

dump_probe() { # $1=probe 名（probe_<name>.html） $2=虚拟时间预算ms → stdout DOM
  local name="$1" budget="$2"
  timeout 300 "$EDGE" --headless=new --disable-gpu --no-first-run \
    --no-default-browser-check --user-data-dir="$PROFILE" \
    --window-size=440,980 --virtual-time-budget="$budget" --timeout=280000 \
    --dump-dom "http://127.0.0.1:8931/probe_${name}.html" 2>/dev/null || true
}

probe_once() { # $1=name $2=PASS 标记 $3=budget → 0/1
  local dom
  dom=$(dump_probe "$1" "$3")
  echo "$dom" | grep -q "$2"
}

probe_with_retry() { # $1=name $2=marker $3=budget（真网探针重试 1 次）
  local ok=FAIL
  if probe_once "$1" "$2" "$3"; then ok=PASS
  else sleep 5; if probe_once "$1" "$2" "$3"; then ok=PASS; fi; fi
  record "$1" "$ok"
  [ "$ok" = "PASS" ]
}

ST=PASS
fail() { ST=FAIL; }

# ---- tier1: boot ----
# 审计修正（2026-10-25）：无头 Edge 长会话后偶发段错误（非应用回归，
# 同批 reader 探针恒绿）——boot 单发改为一次重试，对齐 probe_with_retry
if timeout 90 bash "$ROOT/scripts/lab_check.sh" "书库" "导入" >/dev/null 2>&1 \
  || timeout 90 bash "$ROOT/scripts/lab_check.sh" "书库" "导入" >/dev/null 2>&1; then
  record boot PASS
else
  record boot FAIL; fail
fi

# ---- tier2: 本地稳定探针 ----
# reader：最终断言在 DOM 文本（Repro + 第1页）
dom=$(timeout 300 "$EDGE" --headless=new --disable-gpu --no-first-run \
  --no-default-browser-check --user-data-dir="$PROFILE" \
  --window-size=412,915 --virtual-time-budget=90000 \
  --dump-dom "http://127.0.0.1:8931/probe_reader.html" 2>/dev/null || true)
R=$(echo "$dom" | python -c "
import sys, re
s = sys.stdin.buffer.read().decode('utf-8','ignore')
s = re.sub(r'<script[\s\S]*?</script>', ' ', s)
s = re.sub(r'<[^>]+>', ' ', s)
s = re.sub(r'\s+', '', s)
print('PASS' if ('Repro' in s and '第1页' in s) else 'FAIL')
")
record reader "$R"; [ "$R" = "FAIL" ] && fail

probe_with_retry turso "PROBE-OK" 60000 || fail
probe_with_retry opds_fail "OPDS-FAIL-PROBE-PASS" 120000 || fail

# ---- tier3: 真网探针 ----
probe_with_retry http "HTTP-PROBE-PASS" 180000 || fail
probe_with_retry tts "TTS-PROBE-PASS" 250000 || fail
probe_with_retry opds "OPDS-PROBE-PASS" 300000 || fail

echo "$RESULTS"
echo "$(date '+%F %T')  v3  $ST  $RESULTS" >> "$ROOT/.shots/regression.log"
[ "$ST" = "PASS" ] && exit 0 || exit 1
