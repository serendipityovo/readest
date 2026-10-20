#!/usr/bin/env bash
# R1 设备版本检查（D1 真机窗口第一步）：
# API >= 26 -> 继续；否则触发预案 A（降 compatibleSdkVersion，见 PLAN-D1-D3.md）
set -e
HDC="/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"

TARGETS=$("$HDC" list targets 2>/dev/null | grep -v '^\[Empty\]' | grep -v '^$' || true)
if [ -z "$TARGETS" ]; then
  echo "ERROR: 无设备在线 (hdc list targets = [Empty])"
  exit 1
fi
echo "设备: $TARGETS"

VER=$("$HDC" shell param get const.product.software.version 2>/dev/null | tr -d '\r')
API=$("$HDC" shell param get const.ohos.apiversion 2>/dev/null | tr -d '\r')
NAME=$("$HDC" shell param get const.product.name 2>/dev/null | tr -d '\r')
echo "型号: $NAME"
echo "系统版本: $VER"
echo "API 版本: $API"

if [[ "$API" =~ ^[0-9]+$ ]] && [ "$API" -ge 26 ]; then
  echo "VERDICT: OK (API $API >= 26，直接装机)"
  exit 0
else
  echo "VERDICT: PLAN_A (API $API < 26 —— 降 compatibleSdkVersion 后再装机)"
  exit 2
fi
