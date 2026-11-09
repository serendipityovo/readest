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
| `AppScope/app.json5` `bundleName: com.yueyi.app`（2026-11-06 由 com.readest.app 变更，versionCode 1000002） | 品牌独立彻底化；AGC 侧需新建应用记录并重签发布 Profile（见 PUBLISH.md） |
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

---

## 8. 真机补测（2026-11-06 晚间 · 独立于 §7 修复批次）

> 设备：**HUAWEI MateBook Pro（API 23，系统语言 zh-Hans）**；hdc 来自 `E:\DevEco Studio\sdk`。
> 说明：R1–R8 在**设备原装 debug 构建（10-30 基线，即 §7 修复前代码）**上执行；§7 修复后的包级复验见 R10。

### 8.1 执行与结果（修复前构建）

| # | 测试 | 结果 |
|---|---|---|
| R1 | **SelfTest 64 用例**（`--ps selftest 1` 冷启直达 + `uitest uiInput click` 自动点击「全部运行」+ hilog 逐例采集） | **60 OK / 3 SKIP / 1 THROW**，与文档基线完全一致 |
| R2 | THROW 定性：#63 `download_file` → `http error code 404` | 本机 curl 验证 tuna `favicon.ico` 已全网 404（`.png` 200）→ **测试数据失效，非应用缺陷**；http 错误路径正确上抛 |
| R3 | 主应用冷启动 | KI5 探针全 true、`[SHIM-LOAD] main + ?v=buildstamp`、**零 unhandledrejection / 零 error** |
| R4 | 窗口标题品牌链 | hilog 实证 `set_title raw=Readest` → 桥内替换 → `setWindowTitle ok: 阅易`；截图确认标题栏「阅易」、全界面无 Readest 字样 |
| R5 | V-02 随包发布（修复前） | 旧包 `resources.index` 含 zh_CN "Readest"×3，设备语言 zh-Hans 命中 |
| R6 | V-12 真机可见（修复前） | SelfTest 页标题截图可见「Readest 鸿蒙 · 桥接自测页」 |
| R7 | 文件关联·**冷启动** want | 链路完整触发：handleWant → `deep-link|get_current` 返回 uri ×4 → 前端 ingestFile → `plugin:fs\|open` → **resolve ok=false `"path outside app sandbox"`** → 前端 "Error importing book"（优雅报错不崩溃）→ 书架仍空 |
| R8 | 文件关联·**热启动** want | `shared-intent pending (no listener yet)`：本 build 前端从未注册 shared-intent 监听（invoke 全量 census 无该 register_listener），pendingIntent 无消费者、get_current 不再轮询 → 观察 50s **无反应无提示** |
| R9 | SelfTest 关键通过项抽查 | `colorScheme=dark`（跟随系统深色）、`turso|select → [{"id":1,"v":"hi"}]`、`native-tts|speak → utteranceId`、`fs|read_text_file → [111,107]`、Asset Kit 密钥存取 ✓ |

### 8.2 新增缺陷（并入 §3.1；均未被 §7 修复覆盖，**仍开放**）

| 编号 | 级别 | 描述与真机证据 | 建议 |
|---|---|---|---|
| **V-16** | **P2** | **文件关联导入对沙箱外路径必然失败**：module.json5 声明 7 种 UTD"打开方式"技能，但真实场景送达的 file:// URI 均在 filesDir 外，ingestFile→`fs\|open` 被 `assertSandboxPath` 拒绝（R7 实证）。`importPickedUriToSandbox` 仅接 picker 路径。KI-5"file:// SEND 导入未落盘"残余项实测未闭环；FIDELITY-AUDIT"深链/文件关联=完全一致"与实测不符 | want 路径复用 importPickedUriToSandbox（借临时授权拷入 `filesDir/imports/`）再进 NativeFile |
| **V-17** | **P2** | **热启动文件关联完全无反应**（R8）：shared-intent 监听从未注册、pendingIntent 无消费者、get_current 仅启动期轮询——应用已开时"打开方式"既不导入也不提示 | 前端挂载 useAppUrlIngress 注册监听，或桥在 onNewWant 后主动通知 |
| **V-18** | P3 | `--ps selftest 1` 仅 onWindowStageCreate 生效：应用已运行时走 onNewWant，参数被忽略（R1 首次尝试实证，需 force-stop 后冷启） | onNewWant 处理参数或文档注明 |

与上游差异表增补：**D-8 文件关联导入（"打开方式"）不可用**（冷启动报"导入失败"、热启动无响应）——上游桌面版双击开书可用。

### 8.3 编译门（E3）与签名链（E 环境新发现）

- **ArkTS 编译 + 打包：PASS**（hvigor `assembleHap` 两轮，`BUILD SUCCESSFUL in 41s`；产物 `entry-default-unsigned.hap` 43.4MB）。
- **SignHap：失败——`The certificate has expired! NotAfter: 2026-11-05`**。`~/.ohos/config` 自动签名材料生成于 10-22（约 14 天有效期），**已于 11-05 过期**。此为环境项非代码项。
- 该过期同时解释了本晚所有 `hdc install` 失败（9568322 not trusted app source）：仓库发布证书 hap 本就仅限应用市场渠道；debug 证书又过期 → **当前无任何可直装签名**。
- **§7 修复批次包级复验（R10）**：以修复后源码构建的 unsigned 包内检——`resources.index` **0×"Readest" / 7×"阅易"**、`manifest.json name=阅易`、`.well-known` 已移除、`select_directory` 已传 context（源码 1534 行）→ **V-02/V-08/A5/A6/C 类修复确认进包**；运行时复验待证书续期（见 8.4）。

### 8.4 ⚠️ 设备状态披露与恢复步骤

测试过程中为验证新构建安装执行了 `bm uninstall com.readest.app`（当时包名，现已变更为 com.yueyi.app），随后因 debug 证书过期**无法重装**，设备当前**未安装本应用**。恢复步骤（需人工，约 5 分钟）：

1. 打开 DevEco Studio → File→Project Structure→Signing Configs→勾选 Automatically generate signature，重新登录华为账号生成新 debug 证书/profile（覆盖 `~/.ohos/config`）；
2. `bash scripts/deploy.sh --build`（构建+签名+安装+启动一条龙），预期 `AppMod finish`。

### 8.5 真机小结

- **通过面**：桥命令真实分发 60/64、冷启动零异常、缓存绕过生效、品牌替换链真机生效（主界面零上游品牌泄露）、调试通道关闭、发布证书直装拒绝符合安全预期。
- **缺陷面**：文件关联（V-16/V-17）为真机实测的**功能级缺陷**且未在 §7 修复；V-18 调试入口边界。
- **环境**：debug 证书过期（11-05）导致签名/装机链路阻断，属测试环境维护项，已给出恢复步骤。

---

*报告生成：2026-11-06 · 执行者：ZCode 自动化测试（Web 回归 + 白盒 harness + 品牌扫描 + 配置审查 + 真机 SelfTest/文件关联/编译门/签名链）*

---

## 9. §8 真机缺陷修复记录（2026-11-06 深夜批次）

| 项 | 修复 | 状态 |
|---|---|---|
| **V-16** | `handleWant` 重构：file:// want 先借临时授权拷入 `filesDir/imports/`（`settleWantUri` 双 URI 形态回退），后续 get_current/shared-intent/OPEN_WITH_FILES 全链走沙箱路径；拷贝失败回退旧行为（原始 uri + 优雅报错） | 代码落地，编译门 BUILD SUCCESSFUL；**机制级真机验证通过（§10.2），真实文件管理器场景待人工确认** |
| **V-17** | 无监听时新增第三通道：`pushOpenWithFiles` 经 `runJavaScript` 调用前端库页自备的 `window.OPEN_WITH_FILES([path])` 入口（上游 `processOpenWithFiles` 全量 ingest 语义）；pendingIntent 兜底保留 | 同上（§10.2 实证 push 日志） |
| 冷启动竞态 | `get_current` 等待在飞 `wantSettle`（大文件拷贝 vs 前端启动轮询窗口） | 代码内注释 |
| **V-18** | 备案：`--ps selftest 1` 仅冷启生效，onNewWant 注释注明复测须 force-stop 冷启 | 文档化 |
| R2 | SelfTest download 用例 URL `favicon.ico`→`favicon.png`（tuna .ico 已全网 404，.png 200）+ 落盘扩展名对齐 | 待真机复跑 64/64 |
| **D-8** | 修复方向=对齐上游（上游桌面双击开书可用）：V-16/17 修复后冷/热启动"打开方式"均应可用；验证后从差异表移除 | 待真机 |

验证：`BUILD SUCCESSFUL in 38s`（grep 显式门）。运行时复验依赖调试证书续期（§8.4 步骤，需 DevEco GUI 重签）。

---

## 10. 二轮真机复验（2026-11-07 凌晨 · com.yueyi.app 新包 · §9 修复的运行时验证）

> 背景：工程包名变更为 **com.yueyi.app**（versionCode 1000002）；签名材料经 DevEco 重新申请（新 profile 绑新包名 + 本机 UDID）；`deploy.sh --build` 构建/签名/安装/启动**全绿**，应用已回到设备。

### 10.1 新发现回归与修复（brand_rename 半截改名 · 当场闭环）

| 项 | 内容 |
|---|---|
| 现象 | 新包冷启动出现 `KI5-REJ TypeError: (0,v.isReadestCloudStorageActive) is not a function`（§7 修复批次引入；旧包零 REJ） |
| 根因 | turbopack 把命名导出注册为**带引号的标识符键**（`"isReadestCloudStorageActive": fn`），`brand_rename.py` 只替换字符串字面量 → 键侧改成 `is阅易CloudStorageActive` 而引用侧仍为原标识符，跨模块绑定断裂。同类共 **4 个标识符族**：isReadestCloudStorageActive / isReadestCloudEnabled / persistReadestCloudChoice / getReadestVoiceAPIBaseUrl |
| 修复 | ① 设备包 + lab 副本共 48 个 chunk：两形态统一为 **yueyi** 形式（`isYueyiCloudStorageActive` 等），逐文件 `node --check` 语法门零回滚；② `brand_rename.py` 新增守卫：**整串为标识符形状的字符串一律不改**（防复发） |
| 复验 | 重打包装机后冷启动 **KI5-REJ 归零**；标题链 `set_title raw=阅易 → setWindowTitle ok: 阅易` 正常 |

### 10.2 §9 修复的运行时验证（V-16/V-17 机制级通过）

| 项 | hilog 实录证据 |
|---|---|
| V-16 want 沙箱化 | `handleWant uri=file:///…files/settings.json` → **`picked copied 12763 bytes -> files/imports/settings.json`**（借 want 授权拷贝入沙箱，fs 链路不再被 assertSandboxPath 拒绝） |
| V-17 第三通道 | 无监听时 **`shared-intent push via OPEN_WITH_FILES`**——`window.OPEN_WITH_FILES([...])` 推送，载荷到达前端 |
| 失败回退 | 应用命名空间外路径（/data/local/tmp → 13900002 ENOENT）：`want sandbox copy failed` 后**优雅回退**旧行为，不崩溃 |
| 方法限制 | shell 无法向应用命名空间投送可授权文件（/data/local/tmp 不可见、app 沙箱不可写），**真实文件管理器"打开方式"为最后一公里人工确认项**（约 30 秒） |

### 10.2b 真实"打开方式"三连环根因与终验（2026-11-07 00:48 PASS）

用户以真实文件管理器（右键 epub → 打开方式 → 阅易）复测，暴露 **§9 修复之下的三层连环缺陷**，逐层定位逐层修复：

| # | 缺陷 | 真机证据 | 修复 |
|---|---|---|---|
| ① | **推送当函数调用（恒空操作）**：`window.OPEN_WITH_FILES` 上游语义是**数据数组**（上游赋值后带 reload 导航库页再由 parseOpenWithFiles 读取），桥按 `typeof==='function'` 守卫调用 → 永不执行 | 前端 chunk 反查：`window.OPEN_WITH_FILES=a`（赋数组）+ `parseOpenWithFiles` 读取顺序 `?file=` 参数 → 数组 → 启动URL | pushOpenWithFiles 改为**上游第一优先级契约**：赋数组 + `location.assign('/library?file=<enc>&reload=…')`（数据在 URL，整页导航不丢） |
| ② | **冷启动 context 空指针**：onCreate 时 Index 页未运行，桥 `context=null`，`importPickedUriToSandbox` 读 `context!.filesDir` 抛 TypeError（错误被 JSON.stringify 成 `{}` 掩盖） | `Ability onCreate` 与 `want sandbox copy failed: {}` **同一毫秒**（同步空指针特征） | EntryAbility.onCreate 先 `setContextForTest(this.context)` 再 handleWant；catch 日志改打 code/message |
| ③ | **回填裸路径缺 `file://` 前缀**：拷贝产物以裸沙箱路径回填启动 URL，前端 `isFileUrl` 判定要求 file:// scheme → `Skip non-file URL` 丢弃 | console：`Intent Open with URL: /data/storage/…` 紧跟 `Skip non-file URL: /data/storage/…`（前端已收到、被过滤） | 回填统一 `finalUrl = 'file://' + path`（fsPath 侧本就剥前缀还原） |

**终验（PASS）**：修复后真实文件管理器冷启动"打开方式"全链绿——
```
handleWant uri=file://docs/storage/Users/currentUser/Desktop/hongloumeng.epub
picked copied 1151585 bytes -> files/imports/hongloumeng.epub
shared-intent push via OPEN_WITH_FILES: file:///data/storage/…/imports/hongloumeng.epub
[web] Intent Open with URL: file:///data/storage/…/imports/hongloumeng.epub   ← 无 Skip
fs|open resolve ok=true (rid=1,2,3,4,5…)                                       ← 书被解析读取
```
用户确认：书架出现《红楼梦》。**V-16/V-17/D-8 正式关闭**（与上游"双击开书"行为对齐）。附注：前端 shared-intent 监听仅 `isAndroidApp` 注册（os_type=windows 下恒 false），桥侧 ?file= 通道为其等价替代，此差异已在 ① 修复注释中固化为契约说明。

### 10.3 新包终态

- 装机链路全绿（新 profile 绑 com.yueyi.app + 本机）；resources.index **0×Readest / 7×阅易**；KI5 探针全 true、REJ 零；
- 文件管理器真实"打开方式"冷启动导入 **PASS**（用户确认书架出现《红楼梦》，见 §10.2b 终验）。

### 10.4 V-19 关书白屏（真机实测发现 · 已修复验证）

| 项 | 内容 |
|---|---|
| 现象 | 阅读中点"关书"叉 → 窗口白屏（进程与 web 均存活，仍在收输入事件） |
| 根因 | 上游多窗口语义：关书 = `plugin:window\|close` 关闭书窗口；本移植单窗口对该命令走 default 空操作返回 null，前端在"窗口已关"假设下停止渲染 → 白屏壳。hilog 铁证：`Closing book → invoke plugin:window|close → resolve null` 之后前端静默 |
| 修复 | 桥新增 `plugin:window\|close` case：等价映射为 `location.assign('/library')`（= 上游"关书窗口后露出库窗口"），返回 null 保持 invoke 契约 |
| 复验 | 用户确认：关书叉 → 正常回书架，再开书正常 |

**多窗口移植评估结论**（应询）：单窗口为有意取舍（README 差异表备案）；窗口子系统多控制器化（label 注册表/按窗口注入 shim/窗口事件路由）估算 3–5 天专项+全量回归，建议列为发布后用户反馈驱动的新特性；现阶段策略=补齐单窗口等价映射（window|close 为第一例）。

### 10.5 剩余事项

1. 热启动"打开方式"（应用开着时右键另一本书）走同一推送通道，可选快速复核；
2. AGC 按新包名 com.yueyi.app 重建应用记录 + 重签发布 Profile（上架前必做，PUBLISH.md 清单）；
3. SelfTest 64 用例含 favicon.png 新 URL 的复跑（预期全绿）。

---

## 10. 真机验证闭环（2026-11-10 · com.yueyi.app / 1000006 · 调试签名装机）

### 10.1 验证结果

| 项 | 结果 |
|---|---|
| **SelfTest 64** | 60 OK + 3 SKIP + 1 THROW（KI-7 Clash TLS 环境项）；**#12 字体=真实系统枚举**（楷体-简/书宋-简/方正魏碑…）→ **D-3 真机实证**；#63 URL 无 404 → R2 修复生效 |
| **V-16/V-17 文件关联** | 全链真机打通：授权请求（READ_WRITE_DOCUMENTS_DIRECTORY，用户允许）→ **raw→app 路径翻译**（`/storage/Users/currentUser/Documents/`）→ 沙箱副本 → OPEN_WITH_FILES（file:// 前缀修正）→ ingest → 打开。冷启动全链 hilog 实证 |
| **V-16 根因改写** | 原判"URI 形态"错误——真因=公共 Documents 目录对无授权应用**挂载不可见**（ENOENT 而非 EPERM）。探针实证：授权前 `/storage/media/100/...` 全 ENOENT；授权后应用可见根=`/storage/Users/currentUser/Documents`（6 items 与 raw Docs/Documents 内容一致） |
| **TXT 打开（审核主诉）** | want 链真机全通：GBK 正确解码（王国维《人间词话》繁体正文渲染），**窗口标题「阅易 — gbk_sample」**，阅读页正常 |
| **D-2 分屏** | 「并排阅读」入口存在于书籍菜单（单书态禁用=上游一致）→ 申报即可 |
| **D-1 AI 伴读** | 设备 UI 无入口（未登录态上游不渲染）→ 按审核"设计意图说明"通道申报，无需隐藏 |
| **标签一致性** | 设备标签=阅易阅读器；窗口标题品牌替换链正常（阅易 — 书名） |

### 10.2 遗留

- 付费墙/Premium 入口移除、品牌清洗等 v1.0.2 全部修复已随 1000002-1000006 系列在真机验证
- 备案维持项不变（V-10/11/12/15）
