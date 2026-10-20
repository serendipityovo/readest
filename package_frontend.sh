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
python - <<'EOF' 2>/dev/null || sed -i 's#<head>#<head><script src="/tauri_shim.js"></script>#' "/d/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend/index.html"
import io
p = r"D:/Projects/ReadestOhos/entry/src/main/resources/rawfile/frontend/index.html"
s = io.open(p, encoding="utf-8").read()
tag = '<script src="/tauri_shim.js"></script>'
if tag not in s:
    s = s.replace("<head>", "<head>" + tag, 1)
    io.open(p, "w", encoding="utf-8").write(s)
print("injected")
EOF

echo "[6/6] writing buildstamp (drives incremental extraction on device)..."
date +%s > "$RAW_DIR/buildstamp.txt"

du -s --block-size=1M "$RAW_DIR" | cut -f1 | xargs -I{} echo "frontend packaged: {} MB"
echo DONE
