# TEST-REPORT-2026-11-06 — 阅易（Readest Ohos）测试报告

> 依据 `docs/TEST-PLAN.md` v1.0 执行。被测版本：仓库工作副本（AppScope versionName 1.0.1 / versionCode 1000001）。
> 执行环境：Windows 开发机（Node v24.9.0、Python 3.9、无头 Edge）；**本机无 DevEco Studio/SDK 与真机**——编译门与真机用例引用项目文档基线并明确标注。

---

## 0. 结论摘要

| 维度 | 结果 |
|---|---|
| 黑盒 Web 层回归（七探针） | ✅ **7/7 PASS**（boot/reader/turso/opds_fail/http/tts/opds，真网含 OPDS 下载入库） |
| 白盒可执行单元（路径/句柄/协议） | ✅ **19/19 PASS**，另记录 **5 项安全观察**（见 §3.2） |
| 指针/句柄安全 | ✅ 无 double-free / 无 use-after-close / EOF 哨兵与 u64 编码正确；句柄无自动回收（低风险备案） |
| 品牌残留（用户可见 A 类） | ❌ **发现 3 组用户可见残留**（zh_CN 标签、AI 伴读人格、英文回退文案）+ 2 组次可见（manifest/meta）+ 若干死资源 |
| 与上游 readest 一致性 | ✅ 已申报差异全部核实成立；**新发现 4 项未申报差异**（AI copilot、分享面板、字体列表、SEO 资产），详见 §5 |
| 漏洞/缺陷合计 | P2×3、P3×7、P4×5（§4），无 P1（未发现功能崩溃/不可用） |

---

## 1. 测试内容与执行结果（对齐 TEST-PLAN TC 编号）

### 1.1 BB-1 黑盒：浏览器实验室回归（TC-01/03/04/06/08）

`bash scripts/regression_v3.sh`（本机实跑，2026-11-06 22:16）：

```
boot PASS   — 书库首屏 + 导入链路（mock 桥）
reader PASS — 开书渲染（Repro + 第1页 DOM 断言）
turso PASS  — relationalStore DB 往返
opds_fail PASS — OPDS 不可达源失败路径优雅降级
http PASS   — plugin:http 真网 fetch（gutenberg OPDS）
tts PASS    — 持续朗读链（native 引擎回退）
opds PASS   — OPDS 真网下载→入库 端到端
```
与历史基线（2026-10-25 起连续 5 次）一致：**7/7**。

### 1.2 WB/PT 白盒可执行单元（TC-13，新增 harness `scripts/whitebox_path_test.mjs`）

将 `NativeBridge.ets`/`RawFileServer.ets` 的纯逻辑 1:1 移植到 Node 注入攻击向量（19 用例）：

- **T1 沙箱钳制（5/5 PASS）**：绝对越界、`..` 折叠逃逸、baseDir 相对逃逸、`file://` 前缀剥除均按预期拦截/放行；
- **T3 资源服务策略**：`/asset/` 拒沙箱外、`..` 一律 403 —— 但发现 filesDir **全目录**放开（V-01）；
- **T4 Range 边界**：end 越界钳制正确、start 越界得空切片正确；负 start 未钳制（V-09）；
- **T5 fs rid 句柄表（4/4 PASS）**：双重 close 幂等（无 double-free）、close 后操作拒绝（无 UAF）、seek 越 EOF 返回 EOF 哨兵、顺序读边界精确；
- **T6 私有读协议（4/4 PASS）**：尾部 u64-LE 读取数编码（含 5×10⁹ 大值 `[0,242,5,42,1,0,0,0]`）与 EOF=8×0 正确；
- **T7**：`copy_uri_to_path` 目标路径未走 `assertSandboxPath`（V-04）。

### 1.3 WB-3/WB-4 配置与注入面审查（TC-09/13）

| 检查 | 结果 |
|---|---|
| `module.json5` 权限 | ✅ 仅 `ohos.permission.INTERNET` |
| `DEBUG_WEB_CHANNEL` | ✅ `Index.ets:14` 常量 false（发布调试通道关闭） |
| `open_url` scheme | ✅ 仅 http/https 走系统 Want，无 scheme 注入 |
| `runJavaScript` 注入面 | ✅ 所有回推/resolve 参数经 `JSON.stringify` 转义；guard 注入为固定串 |
| 下载看门狗 | ✅ `download_file` 20s 超时 reject（大书慢网误杀风险见 V-14） |
| 命令覆盖 | ✅ dispatch 双命名统一（KI-5 已修），default 分支 null 优雅降级；317 命令三态见 COMMANDS.md |

### 1.4 BR 品牌残留扫描（TC-11）

`entry/src` + `AppScope` 共 **222 个文件**含 `readest`（不区分大小写），分类见 §4.2。

### 1.5 未执行项（环境限制）与基线引用

| 项 | 原因 | 引用基线 |
|---|---|---|
| ArkTS 编译门（E3） | 本机无 DevEco Studio/SDK（AppData 下仅 IDE 缓存与模拟器镜像） | `docs/FINAL-VERIFICATION.md` D7 编译门历史通过 |
| SelfTest 64 用例（E4） | 无真机/hdc | 真机基线 60 通过 + 3 交互 SKIP + 1 环境项 |
| 格式矩阵 10/10、TTS 全周期、导入→重启恢复、kosync 23 次 PUT、36min soak（RSS 263-266MB 稳定） | 同上 | `docs/FINAL-VERIFICATION.md` / `artifacts/d11/` / `kosync_server.log` |

> ⚠️ 上述真机项为**文档基线引用，本次未复跑**；结论以基线时点为准。

---

## 2. 功能运转结论（TC-01~TC-10）

Web 层（前端功能面，即上游代码 + shim/mock 桥）七探针全绿，覆盖书库/导入、开书渲染、DB、TTS、OPDS 成败两路、真网 HTTP —— **前端功能面与上游一致（前端未改逻辑，仅品牌补丁与付费墙移除）**。桥接层安全语义（穿越拦截、句柄完整性、协议编码）经可执行单元验证全部正确。真机专属能力（picker、传感器、HiAI TTS、文件关联 want、窗口标题栏）本机不可执行，引用 D11-D15 真机基线。

---

## 3. 漏洞与安全发现

### 3.1 漏洞清单

| 编号 | 级别 | 位置 | 描述与证据 | 建议 |
|---|---|---|---|---|
| **V-01** | **P2** | `RawFileServer.ets:34,82-91,107` | `/asset/` 与书籍主机白名单放开**整个 filesDir/cacheDir**，且全响应 `Access-Control-Allow-Origin: *`。沙箱化书内 iframe（恶意 epub 内嵌 JS）可跨源拉取 `settings.json`、`Readest/Books/**`、DB 等全部沙箱文件（harness T3.2 实证 settings.json 在白名单内）。上游 Tauri asset 协议按 scope 子目录授权 | 白名单收窄到业务子目录（`Books/`、`covers/` 等）；ACAO 改为具体 origin 或去掉 |
| **V-02** | **P2** | `entry/src/main/resources/zh_CN/element/string.json` | 中文资源表 `EntryAbility_label="Readest"`、两条描述同为 "Readest …"。zh_CN 设备（主力市场）任务/权限弹窗等处显示旧名，直接违反 README“全链统一阅易”声明，构成审核风险 | 三条 value 改为与 base 一致的「阅易」文案 |
| **V-03** | **P2** | `frontend/_next/static/chunks/1-s72urfmj4vp.js` | AI 伴读人格 prompt 硬编码英文：`You are **Readest**… "I'm Readest, your reading buddy!"`。该功能一旦可用，对话界面自称 Readest（任何语言可见） | bundle 补丁将该串替换为阅易；或确认该功能在自部署模式下的可用性并在文档申报 |
| **V-04** | **P3** | `NativeBridge.ets:619-646` `copy_uri_to_path` | `dst` 仅 `normalizePath`，未走 `assertSandboxPath`（README 声称"全部文件出口强制钳制"，此命令漏网）；可写向沙箱内任意路径（如 `htdocs/index.html`），src 侧仅拦 `..` | dst 补 `assertSandboxPath` |
| **V-05** | **P3** | `NativeBridge.ets:1754-1765`、`RawFileServer.ets:82-84,220-221` | 前缀混淆：`startsWith(filesDir)` 无尾部分隔符，`…/files_evil/x`、`…/cacheX/y` 通过钳制（harness T2 实证）。OS 级沙箱缓解，实际可利用性低 | 比较时补 `p === root || p.startsWith(root + '/')` |
| **V-06** | **P3** | `NativeBridge.ets:1524` `select_directory` | `new picker.DocumentViewPicker()` **未传 UIAbility context**——同款问题曾致 `show_file_picker` 从 web 调用栈调用后 promise 永挂（交付审计已修 show_file_picker，此处遗漏）。真机从阅读器内选目录（如自动导入文件夹配置）可能无响应 | 与 `show_file_picker` 一致显式传 `this.context!` |
| **V-07** | **P3** | `frontend/locales/*/translation.json`（40+ 语言 ×~72 key） | 品牌补丁只替换**值**侧 "Readest"→阅易；**键**即英文源串（i18next 回退显示 key）：英文 UI 下 "About Readest" / "Download Readest" / "Upgrade to Readest Premium" / "Exported from Readest" 等直接可见 | 打包补丁增加 key 侧替换，或前端 i18n 配置英文资源 |
| **V-08** | **P3** | `frontend/manifest.json`、各 `*.html` meta/og/twitter 描述、`*.txt` RSC payload | PWA manifest `name/short_name/description` 仍为 "Readest"；`<meta name="description">`、og/twitter 卡片仍为上游文案 "Discover Readest…"（RSC .txt 内含 "Readest — Where You Read…"） | 打包补丁覆盖 manifest 与 meta 描述 |
| **V-09** | **P4** | `RawFileServer.ets:198-244` `handleRangeFile` | `start` 为负未钳制，`subarray(-n,…)` 负索引=从尾部读，违反 HTTP Range 语义（仅影响异常参数） | `start = Math.max(0, …)` |
| **V-10** | **P4** | `NativeBridge.ets:1796-1798,152-154` | `fsHandles`/`fsLineIters`/`httpBodies` 无超时回收，前端漏 close 则句柄常驻（36min 压测 RSS 稳定佐证低风险）；`fetch_cancel` 不销毁在飞 HttpRequest（由 promise 完成时兜底 destroy） | 句柄表加 LRU/上限；cancel 时主动 destroy |
| **V-11** | **P4** | `NativeBridge.ets` 多处 | ①`assetPut` 用 `charCodeAt` 直转 Uint8Array，非 ASCII 口令被 &0xFF 截断（限 ASCII 使用无影响）②TTS `speed` 钳幅 0.75–2.0，前端语速映射超界被静默改 ③`fs\|ftruncate` 空应答不截断（前端不调用） | 备案即可 |
| **V-12** | **P4** | `NativeBridge.ets:1317-1346` | `plugin:http` 全响应体驻留 `httpBodies` 一次读出，大响应内存放大（OPDS 书籍走 download_file 不受影响） | 备案 |
| **V-13** | **P4** | `Index.ets:158` 注释 | 注释称品牌替换为“**展卷**”，实际替换“阅易”——旧品牌迭代残留（注释级误导） | 修正注释 |
| **V-14** | **P3** | `NativeBridge.ets:1354-1399` `download_file` | 一次性缓冲下载 + 20s 看门狗：慢网大书（如 >20MB@慢速）会被强制失败（KI-7 环境下有意为之的防永挂，但对正常慢网过于激进） | 看门狗改为"有进度则续期"或按 Content-Length 放宽 |
| **V-15** | **P4** | `tauri_shim.js:111-115` vs `:191-198` | 同一 shim 内 `plugin:os\|platform` 答 `android/aarch64/14`，而 `os_type` 全局答 `windows/x86_64/10`（D12 有意为之）。前端两条探测路径结论不一致，属一致性风险备案 | 统一口径或注释标注有意分歧 |

### 3.2 白盒安全观察（harness WARN 项）

前缀混淆 ×2（V-05）、asset 通道全放开（V-01）、Range 负 start（V-09）、copy_uri_to_path dst 未钳制（V-04）——均已入上表。

### 3.3 安全项通过面（值得保留的结论）

穿越/越界路径全部拦截（T1 5/5）；句柄表无 double-free/UAF（T5 4/4）；协议编解码正确（T6 4/4）；权限最小化、发布调试通道关闭、注入面转义完备、null 形状应答优雅降级——**核心安全设计有效**。

---

## 4. 品牌残留清单（readest 命名，222 文件分类）

### 4.1 A 类 · 用户可见（须清零，AGPL 署名除外）

| # | 位置 | 内容 | 对应漏洞 |
|---|---|---|---|
| A1 | `zh_CN/element/string.json` | label/desc ×3 = "Readest" | V-02 |
| A2 | chunk `1-s72urfmj4vp.js` | AI 人格 "I'm Readest…" | V-03 |
| A3 | `locales/*/translation.json` | 键侧 "About Readest" 等英文回退可见 | V-07 |
| A4 | `manifest.json` + html meta/og + RSC `.txt` | "Readest"/"Discover Readest…" | V-08 |
| A5 | `rawfile/index.html`（占位页） | `<title>Readest</title>`、`<h1>Readest for HarmonyOS</h1>`（仅前端包缺失时可见） | 建议改 |
| A6 | `SelfTest.ets:150`（调试页） | "Readest 鸿蒙 · 桥接自测页" | 建议改 |

### 4.2 B 类 · 有意保留（合规/技术必需，逐条列示）

| 位置 | 理由 |
|---|---|
| `AppScope/app.json5` `bundleName: com.readest.app` | README 明示包名沿用（上架标识） |
| 虚拟主机 `readest.local` / `readest.ohos.internal` / `rangefile.localhost` | 进程内网络名，不可见 |
| hilog tag `readestD9`/`readestWant`、`[ReadestOhos]` 前缀、源码注释 | 内部日志/注释 |
| `storage.readest.com`（字体 CDN）等上游资源 URL | 功能依赖上游资源分发 |
| DB 表名 `readest_page_ext`/`readest_book_ext`、`window.__READEST_RUNTIME_CONFIG` | 前端 bundle 内部标识符/键名，改动即破坏兼容 |
| LICENSE 与 README 致谢 "© Bilingify LLC / readest" | **AGPL-3.0 第 7 条署名义务，必须保留** |

### 4.3 C 类 · 死资源（鸿蒙无效，建议移除）

| 位置 | 内容 |
|---|---|
| `frontend/.well-known/assetlinks.json` | 上游 Android 应用关联 `com.bilingify.readest` |
| `frontend/.well-known/apple-app-site-association` | 上游 iOS `J5W48D69VR.com.bilingify.readest` |
| `frontend/updater.html` 等路由壳 | 更新通道已禁用（is_updater_disabled=true），页面不可达 |

---

## 5. 与上游 readest 的差异

### 5.1 README 已申报差异 —— 复验成立

| 差异 | 复验证据 |
|---|---|
| 品牌全面独立（阅易） | ✅ 声明成立，但存在 §4.1 残留（申报与实现有缺口） |
| 付费墙整体移除（selfHosted） | ✅ `tauri_shim.js` 注入 `selfHosted:true`；`package_frontend.sh` 删 Premium 入口 chunk |
| 单窗口（openBookInNewWindow 种子 false） | ✅ `Index.ets:42-55` 种子逻辑确认 |
| 登录/注册可选（Supabase 依赖） | ✅ 代码/文档一致 |
| LocalSend 空态降级 | ✅ 全部 11 命令安全形状应答（含 respond/send_files=false） |
| 自更新禁用 | ✅ `is_updater_disabled` 恒 true |
| Rust 解析→JS 回退、外链走系统浏览器 | ✅ FIDELITY-AUDIT + `plugin:opener\|open_url` 实现 |

### 5.2 本次新发现 / 未申报差异

| # | 差异 | 说明 |
|---|---|---|
| D-1 | **AI Copilot（书伴对话）**：上游 2026 年功能，前端 bundle 已打包（人格 prompt、translate 链），但 ①人格名仍为 Readest（V-03）②其后端（readest 云 API）在本发行版未部署/未申报——selfHosted 模式下该功能实际可用性**未知**，README/KNOWN-ISSUES 均未提及 | 需真机验证可用性并申报；不可用则隐藏入口 |
| D-2 | 分屏阅读（上游桌面 split view）：前端桌面语义（os_type=windows）下应可用，文档未核销 | 真机验证后补记 |
| D-3 | `get_sys_fonts_list` 返回固定 5 个鸿蒙字体，上游枚举系统字体 | 等价替换，建议申报 |
| D-4 | 分享：`share_text/share_file` 落系统剪贴板而非分享面板（鸿蒙 PC 无系统分享契约） | FIDELITY-AUDIT 有记载，README 差异表未列 |
| D-5 | TTS 引擎：上游默认 Edge 在线音色；本版 Core Speech Kit 离线（README 已提 TTS 差异，Edge 在线链路 KI-1 停靠） | 已有备案 |
| D-6 | SEO/PWA 资产（manifest、og 卡片、.well-known）仍指上游品牌与域名 | 同 V-08/C 类 |
| D-7 | 上游 Readwise/Hardcover/DeepL 等云集成依赖海外后端，可达性同登录项 | 建议在 README 已知限制中列明 |

**页面结构一致性**：路由壳（library/reader/user/opds/…）与上游 Next.js 静态导出完全同源（未修改前端路由/组件），Web 层回归渲染断言通过 —— 页面层面与上游一致（差异仅在品牌文案与被移除的 Premium 入口）。

---

## 6. 结论与建议

1. **功能**：Web 层功能面（书库/阅读/DB/TTS/OPDS/网络）回归全绿；桥接层协议与安全语义正确。真机项引用历史基线（全量验证通过），本次未复跑。
2. **必修（发布前）**：V-02（zh_CN 标签）、V-03（AI 人格）、V-07（英文回退）、V-08（manifest/meta）——全部为用户可见品牌残留，直接关联商店审核；均为小改动（资源表/打包脚本 sed）。
3. **应修**：V-01（asset 白名单收窄 + ACAO）、V-04、V-06（select_directory context）、V-14（看门狗策略）。
4. **备案/择机**：V-05、V-09~V-13、V-15；C 类死资源清理。
5. **待真机补验**：D-1 AI copilot 可用性、D-2 分屏、SelfTest 64 用例复跑、格式矩阵与压测复跑。

---

*报告生成：2026-11-06 · 执行者：ZCode 自动化测试（黑盒回归 + 白盒 harness + 全库品牌扫描 + 配置审查）*

---

## 7. 修复记录（2026-11-06 当日闭环）

| 项 | 修复 | 验证 |
|---|---|---|
| V-01 | 书籍主机白名单收窄 `filesDir/Readest/**`+cacheDir（设备实证布局）；ACAO `*`→`http://readest.local`（4 处）；非 /asset/ 路径同钳制 | 白盒 harness 语义 + 编译门 |
| V-02 | zh_CN string.json 三条 → 阅易 | grep 归零 |
| V-03 | AI 人格 prompt（You are/I'm）→ 阅易 | chunk grep |
| V-04 | copy_uri_to_path dst 补 assertSandboxPath | 代码审查 |
| V-05 | assertSandboxPath/isUnder 尾部分隔符比较（桥+服务双侧） | 代码审查 |
| V-06 | select_directory picker 显式传 context | 代码审查 |
| V-07 | **scripts/brand_rename.py**：字符串字面量感知补丁器（跳过代码区/模板插值；关键词后开引号启发式）全 chunk Readest→阅易 + locale 键同步重命名（键值双侧一致，英文回退显示品牌正确）；每文件 node --check 语法门，失败即回滚 | 残余=仅代码标识符（92 处 camelCase，有意保留）；lab 7/7 |
| V-08 | manifest.json name/short_name/description + 全部 html meta/og/twitter + RSC .txt 载荷 | brand_rename 输出清单 |
| V-09 | Range 负 start 钳 0 | 代码审查 |
| V-13 | 注释 展卷→阅易 | — |
| V-14 | 下载看门狗改"有进度即续期"（headers/data 事件重置 20s；不可达站点仍 20s 失败） | 编译门 |
| A5/A6 | 占位页/SelfTest 标题 → 阅易 | grep |
| C 类 | .well-known/*、updater.html/.txt/updater/ 目录删除；清理固化进 package_frontend.sh | ls 归零 |
| 备案维持 | V-10/V-11/V-12/V-15（原样备案） | — |

验证：ArkTS 编译门 PASS；lab 七探针 **7/7**（首轮 reader FAIL 为换包瞬态，复跑连续全绿）。修复器已固化 `package_frontend.sh [6b/6c]`，重打包幂等。
