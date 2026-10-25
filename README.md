# Readest OHOS

HarmonyOS（鸿蒙）移植版 [readest](https://github.com/readest/readest) —— 本地优先的电子书阅读器。

基于 ArkUI `Web` 组件 + tauri_shim 兼容层 + ArkTS NativeBridge 实现，与上游桌面版功能 1:1 对齐（阅读/标注/笔记/TTS 听书/进度同步/OPDS）。同一 AGPL-3.0 许可证发布。

## 特性

- 格式：EPUB / PDF / MOBI / AZW3 / FB2 / CBZ / TXT（含 GBK），竖排支持
- 标注高亮、笔记、书签（epubcfi 精确落盘，重启恢复）
- TTS 语音朗读（Core Speech Kit，后台连续朗读）
- KOReader 同步协议（自配服务器）、WebDAV 备份、OPDS 在线书城
- 深浅色跟随系统、字号字体行距全可调
- 本地优先：书库与阅读数据全部存于设备沙箱，遥测默认关闭

## 构建

需要 DevEco Studio（含 HarmonyOS SDK）与 Node.js。

```bash
# 1) 前端静态包由上游 readest（Next.js export）产出，脚本打 into rawfile/
#    见 package_frontend.sh 中的路径约定
# 2) 打开 DevEco Studio 构建，或命令行：
hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon
```

签名材料不入库（`signing/` 已在 `.gitignore`）。本机构建请按
`build-profile.signing.example.json5` 的结构配置本地签名，或在 DevEco
「项目结构 → 签名配置」里生成。

## 架构速览

```
entry/src/main/ets/
  pages/Index.ets            # ArkWeb 宿主（本地 RawFileServer 托管前端）
  pages/SelfTest.ets         # 64 用例桥接自测页
  services/NativeBridge.ets  # 317 命令桥：fs/turso/http/tts/window/...
  services/RawFileServer.ets # 本地资源服务 + 沙箱路径钳制
docs/                        # BUILD/COMMANDS/KNOWN-ISSUES/PUBLISH 等全套文档
```

上游 Tauri 前端经 `tauri_shim.js` 在 ArkWeb 内运行：`plugin:*` 命令桥接至
NativeBridge，语义以 Android Kotlin 参考实现为基准双端对齐。

## 许可证

AGPL-3.0（见 [LICENSE](LICENSE)）。基于 [readest](https://github.com/readest/readest)
移植，上游版权归其作者所有；本移植版的修改同样以 AGPL-3.0 公开。
