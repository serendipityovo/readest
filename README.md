# 阅易（Yueyi）— HarmonyOS 电子书阅读器

> 阅易是一款运行于 HarmonyOS（含 PC/2in1 设备）的**本地优先**电子书阅读器，
> 基于开源项目 [readest](https://github.com/readest/readest)（AGPL-3.0）移植构建。
> 应用商店名「阅易阅读器」，包名 `com.yueyi.app`（2026-11-06 由 com.readest.app 变更，商店侧需同步新建应用）。

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](LICENSE)

---

## 目录

- [项目简介](#项目简介)
- [功能特性](#功能特性)
- [与上游的差异](#与上游的差异)
- [架构](#架构)
- [目录结构](#目录结构)
- [环境要求](#环境要求)
- [构建指南](#构建指南)
- [测试体系](#测试体系)
- [安全设计](#安全设计)
- [已知限制与降级项](#已知限制与降级项)
- [上架与合规](#上架与合规)
- [文档索引](#文档索引)
- [致谢与许可](#致谢与许可)

---

## 项目简介

上游 readest 是一款 Tauri 2.x + Next.js 的跨平台阅读器（Windows/macOS/Linux/Android/iOS/Web）。
本项目将其**功能完整地**移植到 HarmonyOS：不修改上游前端代码，通过
**ArkWeb 容器 + Tauri 兼容层（shim）+ ArkTS 原生桥（NativeBridge）** 三层结构，
让未打改动的 readest 前端静态包直接运行在鸿蒙设备上，桥接层实现了前端调用的
全部 317 条原生命令。

移植目标与上游桌面版 **1:1 对齐**（阅读、标注、笔记、TTS 听书、同步、OPDS 等
用户可见功能一项不少；实现层允许等价替换——SQLite→relationalStore、Rust 解析→
JS 回退、系统 TTS→Core Speech Kit）。

- **目标设备**：HarmonyOS PC / 2in1（在 HUAWEI MateBook Pro，API 23 真机全量验证）
- **首发渠道**：华为应用市场（AppGallery）
- **版本**：1.0.1（versionCode 1000001）

## 功能特性

### 阅读核心
- **格式矩阵（10/10 真机验证）**：EPUB / PDF / MOBI / AZW3 / FB2 / CBZ / TXT
  （含 GBK 编码）、竖排排版、大体积 PDF、扫描件
- 深浅色主题跟随系统、字号/字体/行距全可调、翻页与滚动双模式
- 阅读进度自动保存（epubcfi 精确到段落），重启恢复
- 书内搜索、章节目录跳转、书签

### 标注与笔记
- 高亮（多色）、下划线、笔记、书签，全部本地落盘
- 精确 epubcfi 定位，跨会话稳定恢复

### 听书（TTS）
- Core Speech Kit 系统语音引擎，支持语速/音调调节
- 后台连续朗读、锁屏续读、焦点切换不中断（HiAI 离线引擎真机验证）

### 数据与同步（全部可选、用户自主配置）
- 本地书库：relationalStore（SQLite 语义）存储书籍元数据与进度
- **KOReader 同步协议**（自配服务器，kosync v1 兼容，真机 23 次真实 PUT 验证）
- **WebDAV 备份**（自配网盘）
- **OPDS 在线书城**（用户自配源，OPDS 目录浏览/下载入库）

### 隐私姿态
- 本地优先：书籍、进度、标注、设置全部存于设备应用沙箱
- 匿名使用统计**默认关闭**（opt-in，关闭态零网络请求）
- 无广告、无推送、无内置书城、不分发任何内容
- 仅声明 `ohos.permission.INTERNET` 一项权限（最小权限）
- 首启隐私弹窗由 AGC「隐私声明托管」系统标准化弹窗承载

### 品牌
- 应用名「阅易」，窗口标题、页面标题、界面文案、图标全链统一
- 图标：墨青渐变底 + 白色翻开书本（书籍元素设计）

## 与上游的差异

本项目是 readest 的独立发行版（fork），除平台移植外，做了以下**有意的**产品调整：

| 调整 | 原因 |
|---|---|
| 品牌：阅易（名称/图标/文案全面独立） | 与上游官方发行版区分（应用商店审核要求，审核指南 9.5） |
| **付费墙整体移除**：构建启用上游 `selfHosted` 自部署模式（全部功能免费解锁），设置菜单 Premium 入口与套餐对比页不渲染 | 本发行版不运营上游的 Stripe 支付后端与账号体系，付费入口对本版用户是死路 |
| 单窗口架构：`openBookInNewWindow` 首启种子为 false，开书在当前窗口内导航 | 移植层为单 ArkWeb 窗口，无多窗口能力 |
| 登录/注册保留但标注为可选 | 依赖上游 Supabase 海外后端，大陆网络可能不可达；核心功能 100% 离线可用 |
| LocalSend 局域网传输降级为空态 | 上游为 Rust 实现；桥接层返回安全形状，功能页显示"无设备"而非报错 |
| 自更新通道禁用（`is_updater_disabled=true`） | 应用市场分发，绕市场更新会被驳回 |
| 分享（引文/书摘）落系统剪贴板 | 鸿蒙 PC 无系统分享面板契约；复制后可自行粘贴到任意应用 |
| Readwise / Notion / DeepL / Google Drive / OneDrive 等云集成依赖上游海外后端 | 与登录项同因：服务端在海外，大陆网络可能不可达；本地阅读功能不受影响 |

上游版权署名（© Bilingify LLC 等）依据 AGPL-3.0 第 7 条**完整保留**。

## 架构

```
┌─────────────────────────────────────────────────────────┐
│  HarmonyOS (ArkUI)                                       │
│  ┌───────────────────────────────────────────────┐      │
│  │  ArkWeb (Web 组件)                             │      │
│  │  ┌─────────────────────────────────────────┐  │      │
│  │  │  readest 前端（Next.js 静态导出，未修改）  │  │      │
│  │  └──────────────┬──────────────────────────┘  │      │
│  │                 │ window.__TAURI_INTERNALS__   │      │
│  │  ┌──────────────▼──────────────────────────┐  │      │
│  │  │  tauri_shim.js（Tauri v2 兼容层）         │  │      │
│  │  │  · invoke 命令转发到原生桥                │  │      │
│  │  │  · 注入全局（metadata/os_type/event…）    │  │      │
│  │  │  · document.title 品牌劫持                │  │      │
│  │  │  · selfHosted 发行模式注入                │  │      │
│  │  └──────────────┬──────────────────────────┘  │      │
│  └─────────────────┼ window.__ohosBridge ─────────┘      │
│                    ▼                                      │
│  ┌───────────────────────────────────────────────┐      │
│  │  NativeBridge.ets（ArkTS 原生桥，317 命令）     │      │
│  │  fs/turso/http/tts/window/dialog/picker/…     │      │
│  └───────────────┬───────────────────────────────┘      │
│                  ▼                                        │
│  @ohos.fileIo / relationalStore / net.http /              │
│  Core Speech Kit / pasteboard / picker / window …         │
└─────────────────────────────────────────────────────────┘
        本地资源由 RawFileServer（应用内 HTTP 服务）提供
        http://readest.local ←→ rawfile/frontend 与沙箱文件
```

**关键技术决策**（详细勘误记录见 `docs/KNOWN-ISSUES.md`）：

- **`os_type: 'windows'`**（而非 android）：readest 前端的 openFile 对 windows 语义
  走 NativeFile（fs|open/fstat 直读），与移植层的文件桥完全契合；android 语义会走
  RemoteFile（Range 请求）路径
- **readest 私有 fs 协议**：`fs|read` 顺序读、尾部 8 字节小端 u64 读取数（0=EOF）、
  `fs|seek` 数字 whence、rid 句柄表——从 dist-js 反汇编确认，非标准 Tauri 协议
- **缓存根治**：加载 URL 带 `?v=<buildstamp>` + 全响应 `Cache-Control: no-store`，
  杜绝 ArkWeb HTTP 缓存供旧页面造成的"幽灵文档"
- **全 shell 加固**：所有路由 shell（library.html 等）注入 pre shim + 内联 shim +
  defer 化，防硬导航/iframe 场景 shim 缺失
- **Tauri 传参勘误**：`plugin:window|set_title` 的标题参数键是 `value` 不是 `title`
  （@tauri-apps/api window.js），用于窗口标题品牌替换

## 目录结构

```
ReadestOhos/
├── AppScope/                    # 应用级配置（app.json5、分层图标、名称）
├── entry/src/main/
│   ├── ets/
│   │   ├── pages/Index.ets      # ArkWeb 宿主页（加载、桥注册、种子设置）
│   │   ├── pages/SelfTest.ets   # 64 用例桥接自测页
│   │   ├── services/NativeBridge.ets   # 核心桥（317 命令分发）
│   │   ├── services/RawFileServer.ets  # 本地资源服务 + 沙箱钳制
│   │   ├── services/NativeDatabase.ets # relationalStore 直通
│   │   └── services/NativeTts.ets      # Core Speech Kit 封装
│   ├── resources/rawfile/
│   │   ├── tauri_shim.js        # Tauri 兼容层（打包时内联进各 html）
│   │   └── frontend/            # readest 前端静态包（含品牌补丁）
│   └── module.json5             # 权限（仅 INTERNET）、ability、图标
├── package_frontend.sh          # 前端打包：拷贝→shim 内联→品牌补丁→buildstamp
├── scripts/
│   ├── regression_v3.sh         # 浏览器实验室回归（7 探针）
│   ├── lab_check.sh / lab_up.sh # 实验室冒烟/起服
│   ├── soak_test.sh             # 20 分钟翻页压测 + RSS 采样
│   ├── devtools_eval.mjs        # DevTools 遥控 CLI
│   └── kosync_server.py         # KOReader 同步协议测试服务器
├── .browserlab/                 # 浏览器实验室（mock 桥 + 探针页）
├── docs/                        # 全套工程文档（见文档索引）
├── testcorpus/                  # 测试书库（epub/mobi/azw3/pdf/gbk txt/竖排）
├── signing/                     # 签名材料（gitignore，永不入库）
└── build-profile.json5          # 构建配置（仓库版脱敏，本地私有版见 signing/）
```

## 环境要求

- **DevEco Studio**（含 HarmonyOS SDK，API 23+；本项目在 5.0.x + SDK 6.1.0(23) 开发）
- **Node.js**（上游前端构建用，本仓库直接消费其静态产物）
- **Windows 开发机**（PowerShell/Git Bash；脚本兼顾 bash）
- 上游 readest 工作副本（前端 `out/` 产物来源；`package_frontend.sh` 中配置路径）
- HarmonyOS 真机或模拟器（USB 调试；`hdc` 工具随 DevEco 附带）

## 构建指南

### 0）前置：前端静态包

前端来自上游 readest 的 Next.js 静态导出（`apps/readest-app/out`）。
`package_frontend.sh` 完成拷贝、Tauri shim 内联、**品牌补丁**（阅易重命名、
付费墙移除）、pdf.js vendor 注入与 buildstamp：

```bash
bash package_frontend.sh
```

### 1）签名配置（一次性）

签名材料不入库。本机构建时把私有配置放 `signing/build-profile.local.json5`
（结构参考 `build-profile.signing.example.json5`），或在 DevEco
「文件 → 项目结构 → 签名配置」中配置（IDE 自动生成机器加密串）。

> 注意：**发布证书签名包只能经应用市场渠道安装**，hdc 直装会被系统拒绝
> （错误 9568322 not trusted app source）。真机日常回归请用调试签名构建。

### 2）构建命令

```bash
export PATH="/path/to/DevEco Studio/jbr/bin:$PATH"
export JAVA_HOME="/path/to/DevEco Studio/jbr"
export DEVECO_SDK_HOME="/path/to/DevEco Studio/sdk"

# 真机回归包（调试签名，buildMode 仍用 release 保证行为一致）
hvigorw assembleHap --mode module -p product=default -p buildMode=release --no-daemon

# 上架发布包（.app，需 build-profile 指向 release 签名配置）
hvigorw assembleApp --mode project -p product=default -p buildMode=release --no-daemon
# 产物：build/outputs/default/ReadestOhos-default-signed.app
```

### 3）装机与调试

```bash
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.yueyi.app            # 正常启动
hdc shell aa start -a EntryAbility -b com.yueyi.app --ps selftest 1   # 自测页
hdc shell hilog | grep readestD9                                  # 应用日志
```

> 常见 hdc 坏态（`need connect-key`）：`hdc kill && hdc start` 即愈。

## 测试体系

三层验证（移植期确立的工程骨架，全部保留）：

| 层 | 手段 | 覆盖 |
|---|---|---|
| **Web 层** | 浏览器实验室（`.browserlab/`，mock 桥 + 无头 Edge） | 启动/阅读器/数据库/网络失败路径/TTS/OPDS 七探针回归（`scripts/regression_v3.sh`，基线 7/7） |
| **ArkTS 层** | 编译门 + SelfTest 页（64 用例，`--ps selftest 1` 直达，逐用例结果入 hilog） | 全部桥命令真实分发路径验证（基线 60 通过 + 3 交互 SKIP + 1 环境项） |
| **集成层** | 真机（MateBook Pro API23） | 冷启动 2.0s、36 分钟翻页 RSS 无泄漏、格式矩阵 10/10、TTS 全周期、导入→开书→重启恢复全链 |

压测与专项：`scripts/soak_test.sh`（长会话内存）、`scripts/kosync_server.py`
（同步协议端到端）、损坏 epub 容错、缓存旁路攻击负向测试（3/3 拦截）。

## 安全设计

- **沙箱路径钳制**（`assertSandboxPath`）：桥接层全部文件出口（fsPath、
  copy_file、rename、download_file、fs|open）强制 `filesDir/cacheDir` 前缀，
  越界路径直接抛错——复刻上游 Tauri fs scope 语义
- **资源服务白名单**：RawFileServer `/asset/` 通道仅允许 filesDir/cacheDir 前缀，
  `..` 穿越 403
- **最小权限**：仅 `INTERNET`；picker/剪贴板/传感器走系统受控 API 免声明
- **下载看门狗**：download_file 20s 超时保护
- **调试通道门控**：`DEBUG_WEB_CHANNEL` 常量控制 `setWebDebuggingAccess`，
  发布构建必为 false

## 已知限制与降级项

| 项 | 状态 | 说明 |
|---|---|---|
| 登录/云同步 | 可选功能 | 依赖上游 Supabase 海外后端，大陆网络可能不可达（含注册频率限制，服务端行为） |
| LocalSend 局域网传输 | 降级 | 上游 Rust 实现未移植；功能页显示空态（不报错） |
| 多窗口 | 单窗口 | 开书固定当前窗口导航（上游桌面默认新窗口，已按移植能力种子关闭） |
| 内置浏览器/深链外开 | 降级 | 外链统一走系统浏览器（Want） |
| parse_* Rust 加速器 | JS 回退 | 上游用 Rust 解析元数据，移植走 foliate-js 等价链路，全格式验证无功能缺失 |

完整记录：`docs/KNOWN-ISSUES.md`（KI-1~7 + 环境备案）。

## 上架与合规

- **许可证**：AGPL-3.0（与上游一致）。开源许可证即本发行版修改与再分发的
  授权依据；本仓库即完整源码。上游版权署名依许可证第 7 条保留。
- **隐私声明**：由 AGC「隐私声明托管」生成与托管，
  [托管地址](https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2069224619277081280)
  （开发者主体与商店开发者信息一致；应用内首启弹窗由华为系统标准化弹窗承载）
- **分发**：华为应用市场，首发设备 PC/2in1；资费免费，无内购
- **审核记录**：两轮（名称/图标相似性→品牌独立重制；功能异常→付费墙移除/
  品牌清洗/桥接修复）。答复与材料口径见 `docs/STORE-LISTING.md`、`docs/PUBLISH.md`

## 文档索引

| 文档 | 内容 |
|---|---|
| `docs/BUILD.md` / `docs/COMMANDS.md` | 构建细节 / 317 命令三态清单 |
| `docs/ARCHITECTURE.md` | 架构决策记录（含 D6 Rust 决断） |
| `docs/KNOWN-ISSUES.md` | 已知问题与降级备案（KI-1~7） |
| `docs/PUBLISH.md` | 上架流程、证书/Profile、打回风险清单 |
| `docs/STORE-LISTING.md` | 商店材料（介绍/截图/分级/隐私/版权/审核答复口径） |
| `docs/PRIVACY-POLICY.md` | 隐私政策口径底稿（生效版为 AGC 托管版） |
| `docs/FIDELITY-AUDIT.md` | 与上游 1:1 复刻度审计报告 |
| `docs/FINAL-VERIFICATION.md` / `docs/RUNBOOK.md` | 终验记录 / 真机操作手册 |
| `PLAN-15d.md` / `PROGRESS.md` | 15 天移植计划与执行记录 |

## 致谢与许可

- 上游项目：[readest](https://github.com/readest/readest) 及其贡献者、
  [foliate-js](https://github.com/johnfactotum/foliate-js)、pdf.js 等开源组件
- 本项目以 **AGPL-3.0** 发布（全文见 [LICENSE](LICENSE)）：您可以自由使用、
  修改和再分发本软件，衍生作品须同样以 AGPL-3.0 开源并保留版权与许可声明。

© 2026 本项目贡献者。基于 readest（© Bilingify LLC）修改。
