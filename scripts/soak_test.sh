#!/bin/bash
# 偏差①整改：20 分钟翻页 soak + RSS 采样（顺带承载偏差② kosync 流量验证）
HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
export MSYS_NO_PATHCONV=1
OUT=/d/Projects/ReadestOhos/artifacts/d11/soak_result.txt
cd /d/Projects/ReadestOhos

"$HDC" shell "hilog -r" >/dev/null 2>&1
"$HDC" shell "aa force-stop com.yueyi.app" >/dev/null 2>&1; sleep 2
"$HDC" shell "aa start -b com.yueyi.app -a EntryAbility -A ohos.want.action.viewData -U file:///data/storage/el2/base/haps/entry/files/inbox/hongloumeng.epub" >/dev/null 2>&1
sleep 30

PID=$("$HDC" shell "ps -ef | grep 'com.yueyi.app$' | grep -v grep | awk '{print \$2}'" | tr -d '\r')
SOCK=$("$HDC" shell "cat /proc/net/unix" 2>/dev/null | python -c "
import sys,re
socks=[]
for l in sys.stdin.buffer:
    m=re.search(r'webview_devtools_remote_(\d+)', l.decode('utf-8','ignore'))
    if m: socks.append(m.group(1))
print(socks[-1] if socks else '')
")
"$HDC" fport rm tcp:9222 >/dev/null 2>&1
"$HDC" fport tcp:9222 localabstract:webview_devtools_remote_$SOCK >/dev/null 2>&1
echo "=== SOAK pid=$PID sock=$SOCK start=$(date +%T) ===" | tee "$OUT"
"$HDC" shell "cat /proc/$PID/status" | grep VmRSS | tee -a "$OUT"

for round in $(seq 1 10); do
  # 每轮 3 批×15 次翻页，批间隔 8s，轮间隔 ~120s（总 ~20 分钟）
  for b in 1 2 3; do
    node scripts/devtools_eval.mjs "(function(){for(var i=0;i<15;i++){[document,document.body].forEach(t=>{try{t.dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',code:'ArrowRight',keyCode:39,bubbles:true,cancelable:true}));t.dispatchEvent(new KeyboardEvent('keyup',{key:'ArrowRight',code:'ArrowRight',keyCode:39,bubbles:true,cancelable:true}))}catch(e){}})}})();'b'" >/dev/null 2>&1
    sleep 8
  done
  sleep 78
  RSS=$("$HDC" shell "cat /proc/$PID/status" | grep VmRSS | awk '{print $2}' | tr -d '\r')
  echo "round=$round $(date +%T) RSS=${RSS}kB" | tee -a "$OUT"
done
echo "=== SOAK END $(date +%T) ===" | tee -a "$OUT"
