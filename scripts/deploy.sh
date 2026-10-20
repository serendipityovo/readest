#!/usr/bin/env bash
# 部署 Readest 鸿蒙版：构建(可选) + 安装 + 启动
# 用法:
#   ./scripts/deploy.sh          # 只装+启动(用现有 hap，优先 signed)
#   ./scripts/deploy.sh --build  # 先构建再装再启动
set -e
cd "$(dirname "$0")/.."

HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"
BUNDLE="com.readest.app"
ABILITY="EntryAbility"
OUT="entry/build/default/outputs/default"

# --- 设备检查 ---
TARGETS=$("$HDC" list targets 2>/dev/null | grep -v '^\[Empty\]' | grep -v '^$' || true)
if [ -z "$TARGETS" ]; then
  echo "ERROR: 没有检测到设备 (hdc list targets = [Empty])"
  echo "       插上真机并允许 USB 调试后重试"
  exit 1
fi
echo ">> 设备: $TARGETS"

# --- 可选构建 ---
if [ "$1" = "--build" ]; then
  export PATH="/e/DevEco Studio/jbr/bin:$PATH"
  export JAVA_HOME="E:\\DevEco Studio\\jbr"
  export DEVECO_SDK_HOME="E:\\DevEco Studio\\sdk"
  "/e/DevEco Studio/tools/hvigor/bin/hvigorw.bat" assembleHap --mode module -p product=default --no-daemon
fi

# --- 选 hap: 优先 signed，其次最新 ---
HAP=$(ls -t "$OUT"/entry-default-signed.hap 2>/dev/null | head -1)
[ -z "$HAP" ] && HAP=$(ls -t "$OUT"/entry-default-unsigned.hap 2>/dev/null | head -1)
if [ -z "$HAP" ]; then
  echo "ERROR: 找不到 hap，先跑 ./scripts/deploy.sh --build"
  exit 1
fi
echo ">> HAP: $HAP ($(du -h "$HAP" | cut -f1))"
echo "   $([ "${HAP##*-}" = "signed.hap" ] && echo '已签名' || echo '注意: 未签名 hap 大概率安装失败,先完成 SIGNING.md 的自动签名')"

# --- 卸载旧版(避免签名不一致冲突) + 安装 ---
"$HDC" uninstall "$BUNDLE" >/dev/null 2>&1 || true
"$HDC" install -r "$HAP"

# --- 启动 ---
"$HDC" shell aa start -a "$ABILITY" -b "$BUNDLE"
echo ">> 已发出启动命令 ($ABILITY @ $BUNDLE)"
