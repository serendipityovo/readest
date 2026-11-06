# TEST-PLAN.md — 阅易（Readest Ohos）通用测试计划

> 版本：1.0（2026-11-06 制定）
> 适用对象：阅易阅读器（readest 鸿蒙移植版）任意版本的功能验收、安全测试、品牌合规测试与上游一致性测试。
> 本文档为**通用模板**：每次测试执行时按 §7 输出物生成带日期的测试报告（如 `TEST-REPORT-YYYY-MM-DD.md`），逐用例记录结果。

---

## 1. 目的与范围

| 项 | 内容 |
|---|---|
| 测试目标 | ① 验证鸿蒙版每一项用户可见功能可正常运转；② 验证功能与页面与上游 readest 桌面版 **1:1 对齐**（允许文档化的等价替换）；③ 检查更名「阅易」后全链路是否存在 `readest` 残留命名；④ 通过黑白盒与指针/资源安全测试发现漏洞 |
| 被测对象 | `entry/`（ArkTS 宿主与桥接层）、`entry/src/main/resources/rawfile/frontend/`（前端静态包+品牌补丁）、`AppScope/`、`package_frontend.sh` 产物 |
| 不在范围 | 上游 readest 前端本身的缺陷（前端代码不修改，缺陷应回馈上游）；华为 AGC 审核流程本身 |

## 2. 测试基线与参考资料

- `README.md` —— 功能特性与已申报差异（品牌/付费墙/单窗口/LocalSend/更新禁用）
- `docs/COMMANDS.md` —— 317 条桥命令三态清单（实现契约权威表）
- `docs/FIDELITY-AUDIT.md` —— 上游 1:1 复刻度审计基线
- `docs/KNOWN-ISSUES.md`（仓库根）—— 已知问题 KI-1~7 与降级备案
- `docs/FINAL-VERIFICATION.md` —— 真机历史基线（SelfTest 60/64、格式矩阵 10/10、36min 压测、kosync 23 次 PUT）
- 上游功能基线：readest.com/docs（AI TTS / AI 翻译 / AI copilot / 高亮笔记 / 分屏 / 云同步 / KOReader 同步 / Readwise·Hardcover 导出 / OPDS / Calibre）

## 3. 环境矩阵

| 环境 | 用途 | 依赖 | 替代方案（不可得时） |
|---|---|---|---|
| E1 开发机（Windows） | 黑盒 Web 回归、白盒静态审查、品牌扫描、可执行单元 harness | Node.js、Python 3、Edge | — |
| E2 浏览器实验室 | mock 桥 + 无头 Edge 七探针 | `scripts/lab_up.sh`、`.browserlab/` | E1 直跑 `scripts/regression_v3.sh` |
| E3 DevEco 编译门 | ArkTS 编译验证（类型/语法门） | DevEco Studio + SDK(API23+) | 引用最近一次构建记录，标注"未复跑" |
| E4 真机/模拟器 | SelfTest 64 用例、格式矩阵、TTS、导入恢复全链、压测 | hdc + 设备 | 引用 `docs/FINAL-VERIFICATION.md` 基线，标注"未复跑" |

## 4. 测试方法与用例族

### 4.1 黑盒功能测试（BB）
以用户视角驱动，不关心实现。两层：

- **BB-1 实验室回归**（E1/E2）：`bash scripts/regression_v3.sh`，七探针必须全 PASS：
  `boot`（书库+导入）/ `reader`（开书渲染 Repro 第1页）/ `turso`（DB 链）/ `opds_fail`（失败路径）/ `http`（真网 fetch）/ `tts`（持续朗读）/ `opds`（真网下载入库）
- **BB-2 真机旅程**（E4，不可得则引用基线）：导入→开书→翻页→标注→书签→搜索→TTS→重启恢复→KOReader 同步→WebDAV→OPDS→深链/文件关联→外链系统浏览器。

### 4.2 白盒测试（WB）
对桥接层/资源服务源码做审查 + 可执行验证：

| 编号 | 项 | 验证点 |
|---|---|---|
| WB-1 | 沙箱路径钳制 `assertSandboxPath`/`normalizePath` | 穿越（`..`、绝对越界、file:// 前缀、baseDir 逃逸）必须抛错；前缀混淆（`filesDir_evil`）记录为发现 |
| WB-2 | RawFileServer 通道 | `/asset/` 白名单、`..` 403、Range 协议 start/end 边界（越界、负数、NaN）、SPA fallback、no-store 缓存头 |
| WB-3 | 权限与门控 | `module.json5` 仅 `INTERNET`；`DEBUG_WEB_CHANNEL` 发布必为 false；下载看门狗 20s；`open_url` 仅 http/https |
| WB-4 | 注入面 | `runJavaScript` 参数必须经 `JSON.stringify` 转义；shim 注入内容固定字符串 |
| WB-5 | 命令覆盖 | `dispatch` switch 对照 `docs/COMMANDS.md` 三态清单抽查；未知命令 default null 优雅降级 |

### 4.3 指针与资源安全测试（PT）
ArkTS 无裸指针，指针测试等价为**句柄表完整性、越界访问、协议编解码与资源回收**：

| 编号 | 项 | 验证点 |
|---|---|---|
| PT-1 | fs rid 句柄表 | 双重 close 幂等（无 double-free）；close 后 read/write/seek 拒绝（无 UAF）；句柄泄漏面（无超时回收——记录风险） |
| PT-2 | 私有读协议 | `fs\|read` 尾部 8 字节小端 u64 读取数（含 >2³² 值）；EOF=8×0；seek 越 EOF 后读返回 EOF |
| PT-3 | Range 越界 | start/end 越界、负 start（subarray 负索引语义）行为记录 |
| PT-4 | 内存/长稳 | `scripts/soak_test.sh`（20min+ RSS 采样无单调增长）；`fs\|read_file` 大文件整读的内存放大风险 |
| PT-5 | 网络资源 | http fetch_cancel 不销毁在飞请求的影响；`httpBodies` 大响应驻留 |

> 可执行单元 harness：`node scripts/whitebox_path_test.mjs`（把 WB-1/WB-2/PT-1~PT-3 的纯逻辑按源码 1:1 移植到 Node 验证；真机行为仍以 SelfTest 页为准）。

### 4.4 品牌残留测试（BR）
全库扫描 `readest`（大小写不敏感），按可见性分类：

| 类别 | 定义 | 判定 |
|---|---|---|
| A 用户可见 | UI 文案、标题、应用标签、AI 对话人格、manifest、meta 描述 | **必须为 0**（除 AGPL 署名/开源致谢） |
| B 有意保留 | 包名 `com.readest.app`、虚拟主机、日志 tag、代码注释、DB 表名、上游 CDN URL | 允许，逐条列示 |
| C 死资源 | 对上游 iOS/Android 的域名关联文件等在鸿蒙无效的资产 | 建议移除 |

扫描命令（排除构建产物与依赖）：
```bash
python - <<'EOF'
import os,re
pat=re.compile(r'readest',re.I)
for base in ['entry/src','AppScope']:
    for dp,dn,fn in os.walk(base):
        for f in fn:
            p=os.path.join(dp,f); d=open(p,'rb').read().decode('utf-8','ignore')
            if pat.search(d): print(p)
EOF
```

### 4.5 上游一致性对比测试（FD）
对照上游 readest 桌面版功能矩阵逐项核对：
① FIDELITY-AUDIT 基线逐条复验；② 上游新功能（AI copilot、分屏、Readwise/Hardcover、DeepL 翻译等）是否可用/是否已申报差异；③ 页面结构（书库/阅读器/设置/笔记页）与上游一致性抽查。

### 4.6 性能与稳定性（PF）
冷启动计时（基线 2.0s）、翻页流畅度、36 分钟 soak、大书（>50MB PDF）开启与翻页、损坏 epub 容错。

## 5. 功能用例矩阵（核心 TC 清单）

> 每条功能至少 1 正向 + 1 负向用例；下表为验收最低集。

| TC | 功能域 | 用例 | 方法 |
|---|---|---|---|
| TC-01 | 书库 | 首次启动空书架渲染、导入（picker）、分组/排序/搜索、删除 | BB-1/BB-2 |
| TC-02 | 格式 | EPUB/PDF/MOBI/AZW3/FB2/CBZ/TXT(GBK)/竖排/大 PDF/扫描件 各开 1 本 | BB-2 (E4) |
| TC-03 | 阅读 | 翻页/滚动双模式、字号字体行距、深浅色跟随、进度保存与重启恢复（epubcfi） | BB-1/BB-2 |
| TC-04 | 标注 | 多色高亮、下划线、笔记、书签，跨会话恢复定位 | BB-1/BB-2 |
| TC-05 | 搜索 | 书内搜索命中跳转、章节目录跳转 | BB-1/BB-2 |
| TC-06 | TTS | 朗读/暂停/停止、语速音调、后台/焦点切换不中断、锁屏续读 | BB-1/BB-2 |
| TC-07 | 同步 | KOReader 自配服务器 PUT/GET；WebDAV 备份恢复 | BB-2 + kosync_server.py |
| TC-08 | OPDS | 自配源浏览/搜索/下载入库；不可达源的失败路径 | BB-1（opds/opds_fail） |
| TC-09 | 隐私 | 统计默认关闭零外联；仅 INTERNET 权限；沙箱内数据落盘位置 | WB-3 |
| TC-10 | 文件关联 | 文件管理器"打开方式"冷启/热启导入；深链 readest:// 行为 | BB-2 (E4) |
| TC-11 | 品牌 | A 类残留为 0；窗口标题/页面标题/图标全链「阅易」；A 类发现逐条列示 | BR |
| TC-12 | 上游一致 | FD 矩阵逐项核对，新增差异必须出现在报告 §差异表 | FD |
| TC-13 | 安全 | WB-1~WB-5 + PT-1~PT-3 全量 | WB/PT |
| TC-14 | 性能 | 冷启动 ≤3s；soak RSS 漂移 <5%；大书可开 | PF |

## 6. 通过准则与严重级别

- **通过**：BB 七探针 7/7；TC-01~TC-10、TC-13、TC-14 无 P1/P2 未处理项；BR-A 类残留清零或全部有 AGPL 依据；FD 差异全部已申报或列入报告差异表。
- **严重级别**：P1 功能不可用/崩溃/用户可见品牌冲突（审核风险）；P2 安全暴露面或重要功能降级未申报；P3 边界缺陷/低可见残留；P4 代码卫生。

## 7. 输出物

每次执行生成 `docs/TEST-REPORT-YYYY-MM-DD.md`，必含：
1. 执行环境与实际可用工具链；
2. 测试内容与逐项结果（对齐本计划 TC 编号）；
3. 漏洞/缺陷清单（编号、级别、位置、复现/证据、建议）；
4. 品牌残留清单（A/B/C 分类逐条）；
5. 与上游 readest 的差异清单（已申报复验 + 新发现）；
6. 未执行项与原因（环境限制），及引用的历史基线。

## 8. 执行指引（本机快速路径）

```bash
bash scripts/regression_v3.sh          # BB-1 黑盒七探针
node scripts/whitebox_path_test.mjs    # WB/PT 可执行单元（19 用例）
# 品牌扫描：见 §4.4 片段
# E3/E4（编译门/真机）需 DevEco + 设备，缺环境时按 §7-6 引用基线
```
