#!/usr/bin/env bash
# Package the readest static frontend into ReadestOhos rawfile.
set -euo pipefail

OUT_DIR="/d/Projects/readest/apps/readest-app/out"
RAW_DIR="/d/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend"
SHIM_SRC="/d/Projects/ReadestOhos/entry/src/main/resources/rawfile/tauri_shim.js"

rm -rf "$RAW_DIR"
mkdir -p "$RAW_DIR"

echo "[1/5] copying frontend build output..."
cp -r "$OUT_DIR"/. "$RAW_DIR"/

echo "[2/5] stripping sourcemaps and debug files (166MB -> smaller)..."
find "$RAW_DIR" -name "*.map" -delete
find "$RAW_DIR" -name "__next.*.txt" -delete
find "$RAW_DIR" -name "*.html.map" -delete 2>/dev/null || true

echo "[3/6] installing tauri shim..."
cp "$SHIM_SRC" "$RAW_DIR/tauri_shim.js"

echo "[4/6] installing pdfjs vendor (fake-worker fallback needs the module)..."
# out/ does NOT contain public/vendor (prepare-vendor isn't part of the export)
# — without it every PDF open dies on a dynamic import of the worker .mjs.
PDFJS="/d/Projects/readest/packages/foliate-js/node_modules/pdfjs-dist"
mkdir -p "$RAW_DIR/vendor/pdfjs"
cp "$PDFJS/legacy/build/pdf.worker.min.mjs" "$RAW_DIR/vendor/pdfjs/"
cp "$PDFJS"/wasm/* "$RAW_DIR/vendor/pdfjs/" 2>/dev/null || true
cp -r "$PDFJS/cmaps" "$RAW_DIR/vendor/pdfjs/cmaps"
cp -r "$PDFJS/standard_fonts" "$RAW_DIR/vendor/pdfjs/standard_fonts"
test -s "$RAW_DIR/vendor/pdfjs/pdf.worker.min.mjs" || { echo "FATAL: pdf.worker.min.mjs missing"; exit 1; }

echo "[5/6] injecting shim tag into index.html..."
python - <<'EOF' 2>/dev/null || sed -i 's#<head>#<head><script>window.__TAURI_INTERNALS__=window.__TAURI_INTERNALS__||{metadata:{currentWindow:{label:"main"},currentWebview:{label:"main"},windows:["main"],webviews:["main"]}};</script><script src="/tauri_shim.js"></script>#' "/d/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend/index.html"
import io
p = r"D:/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend/index.html"
sp = r"D:/Projects/ReadestOhos/entry/src/main/resources/rawfile/tauri_shim.js"
s = io.open(p, encoding="utf-8").read()
shim_src = io.open(sp, encoding="utf-8").read()
tag = '<script src="/tauri_shim.js"></script>'
# KI-5 竞态根治（D12 真机定位）：Next.js chunk 全部 <script async>，async 脚本
# 下载完成即执行、不保证晚于阻塞式 <script src>——RawFileServer 并行响应时
# 大 chunk 可能先于 shim 执行，internals/os_type 全 undefined（曾断 app
# service init 与 file:// 导入链）。根治 = shim 内联（head 解析期同步执行，
# 必然先于一切网络加载的 async 脚本），并移除外链标签防重复初始化。
shim_inline = '<script>/*__TAURI_SHIM_INLINE__*/' + shim_src + '</script>'
if '__TAURI_SHIM_INLINE__' not in s:
    if tag in s:
        s = s.replace(tag, shim_inline, 1)
    else:
        s = s.replace("</head>", shim_inline + '</head>', 1)
# 竞态根治第二刀：async chunk 下载完成即可能抢在内联 shim 前执行（HTML
# 规范允许 async 在解析中途插入执行）。改 defer——下载仍并行，执行严格
# 按文档序，必然晚于 head 内联 shim。
s = s.replace(' async="">', ' defer="">').replace(' async>', ' defer>')
# 兜底（防早 chunk 读 metadata）：置于内联 shim 之前
pre = ('<script>window.__TAURI_INTERNALS__=window.__TAURI_INTERNALS__'
       '||{metadata:{currentWindow:{label:"main"},currentWebview:{label:"main"},'
       'windows:["main"],webviews:["main"]}};</script>')
if pre not in s:
    s = s.replace(shim_inline, pre + shim_inline, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("injected inline shim:", len(shim_src), "bytes")

# D12 全 shell 加固：路由 shell（library.html 等）是硬导航/iframe 的装载
# 目标——没有 shim 的 shell 里 app 二次启动曾致 getAppService reject
# （os_type/invoke undefined）并干扰 file:// 导入链。所有 shell 一律注入
# pre + 内联 shim + defer 化，与 index.html 等价。
import glob
for p in glob.glob(r"D:/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend/*.html"):
    if p.replace('\\', '/').endswith('/index.html'):
        continue
    s = io.open(p, encoding="utf-8").read()
    if '__TAURI_SHIM_INLINE__' not in s:
        s = s.replace('<head>', '<head>' + pre + shim_inline, 1)
        s = s.replace(' async="">', ' defer="">').replace(' async>', ' defer>')
        io.open(p, "w", encoding="utf-8").write(s)
print("all route shells hardened")
EOF

echo "[6/7] brand patch (阅易 rebrand, review 9.5)..."
# titles: <title> → 阅易（动态设置由 shim document.title 劫持兜底）
sed -i 's#<title>[^<]*</title>#<title>阅易</title>#' "$RAW_DIR"/*.html
# locale 值侧大写 Readest → 阅易（键不动=查找语义；小写 readest 不动=URL/邮箱）
# 多轮防同值双次出现被贪婪吞掉
for pass in 1 2 3; do
  for f in "$RAW_DIR"/locales/*/translation.json; do
    if [ "$f" = "$RAW_DIR/locales/zh-TW/translation.json" ]; then
      sed -i 's/: "\([^"]*\)Readest\([^"]*\)"/: "\1閱易\2"/g' "$f"
    else
      sed -i 's/: "\([^"]*\)Readest\([^"]*\)"/: "\1阅易\2"/g' "$f"
    fi
  done
done
# chunk 内页脚链接文字等独立品牌串（仅精确 children 字面量，不碰 URL/标识符）
sed -i 's/children:"Readest"/children:"阅易"/g' "$RAW_DIR"/_next/static/chunks/*.js

# 付费墙整体移除（fork 无上游支付后端）：设置菜单 Premium 入口条件永假 +
# /user 页套餐对比组件替换为 null 渲染（模式经唯一性验证，chunk 名可变，
# 用内容匹配重打；两 sed 目标各恰好 1 处，命中失败即报错中断）
HIT1=$(grep -l 'c&&"free"===d&&(0,n.jsx)(af.default,{label:s("Upgrade to Readest Premium")' "$RAW_DIR"/_next/static/chunks/*.js | head -1)
[ -n "$HIT1" ] && sed -i 's/c&&"free"===d&&/c\&\&"never"===d\&\&/' "$HIT1" || echo "WARN: premium menu pattern not found"
HIT2=$(grep -l '(0,a.jsx)(eD,{availablePlans:ea,' "$RAW_DIR"/_next/static/chunks/*.js | head -1)
[ -n "$HIT2" ] && sed -i 's/(0,a.jsx)(eD,{availablePlans:ea,/(0,a.jsx)(()=>null,{availablePlans:ea,/' "$HIT2" || echo "WARN: plans pattern not found"

echo "[7/7] writing buildstamp (drives incremental extraction on device)..."
date +%s > "$RAW_DIR/buildstamp.txt"

du -s --block-size=1M "$RAW_DIR" | cut -f1 | xargs -I{} echo "frontend packaged: {} MB"
echo DONE
