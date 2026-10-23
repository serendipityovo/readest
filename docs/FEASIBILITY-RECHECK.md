# 剩余流程可行性复检（D6–D15）· 2026-10-16 D5 收官时点

> 依据：PLAN-15d.md 全量重读 × D1–D5 实证证据（CENSUS.md / PROGRESS.md / regression v2 日志 / 构建记录）。
> 结论先行：**剩余流程整体判定可行，无推翻性风险；风险重心已按设计转移到集成层（D11–12），且出现 3 个日历天缓冲。复检产出 6 项行动调整建议（§3）。**

## 1. 形势对照（计划编写时 vs 现在）

| 维度 | 计划编写时（10-14） | 现状（10-16 D5 收官） |
|---|---|---|
| 进度 | D1 未开始 | D1–D5 全部完成（计划排至 10-19）→ **缓冲 +3 天** |
| Web 层（验证体系 ~70%） | 仅三轮白屏修复实证 | **全绿**：boot/fs/turso/导入/开书/CJK 渲染/1600页分页/翻页/进度/目录/书内搜索/高亮/笔记/设置回显/事件系统，回归 v2 双 probe |
| 设备端 ArkTS（~20%） | ~20 命令草图 | **43 命令编译绿灯** + RawFileServer 三主机（含 rangefile 协议）+ relationalStore 直通 + 标记文件门控 |
| 集成层（~10%，D11-15） | 全部未知 | 未触碰（按计划），但 web 层消灭的 bug 类型（形状契约/协议/时序/事件机制）正是真机日最贵返工项 |
| 修复循环健康度 | 规则预设 | 五天统计：D3=5轮 / D4=7轮 / D5≈6轮，**三振与 8 轮上限从未触发** |

## 2. 逐日重估（仅列证据变化引起的判断修正）

### D6 · Rust 决断日 —— 判定：可行，且风险等级下调
- **B 计划（foliate-js JS 等价解析）从"降级方案"升格为"已半验证的主路"**：D4/D5 全部走 foliate-js——真实 EPUB 解析、元数据抽取、目录、全文搜索、CFI 定位均 lab 实证。cargo check 全红也不阻塞功能集（只影响 Rust 侧性能型能力）。
- 决断门逻辑不变；ARCHITECTURE.md 当日产物。
- 建议：提前至缓冲日执行（见 A5）。

### D7 · 系统集成命令 —— 判定：可行，工作量明确
- 剩余命令 ≈ 70−43 ≈ 27 条，**全部有 census 实名**（无未知命令）；Channel 传输层（register_listener + __deliverEvent）已双向打通——TTS 句子回调、intent 推送的管道现成。
- **新增必做项（复检产出 A2）**：D12 的 SAF picker 返回 `content://` URI，其拷贝路径（Android 参考实现 copyURIToPath 的 OHOS 等价）属本日清单。

### D8 · 网络+模拟器 —— 判定：可行
- `plugin:http|fetch` 是启动期最后一条错误型 null；lab 端 fetch 透传有真实出网能力（语料下载已证，代理 7897 可用）。
- 模拟器 checkpoint 未变：华为账号依赖已预设降级（记清单不阻塞）。

### D9 · 系统入口 —— 判定：风险较计划编写时下降
- 文件关联的**完整机制已在 lab 复刻**（D5：shared-intent 事件 → 自动导入）。设备端剩余工作收窄为 want→事件的桥接（EntryAbility/onNewWant → __deliverEvent 至 shared-intent 通道）——管道已验证。
- 图标/启动画面/显示名/深色声明：纯资源+编译门。

### D10 · 总预演 —— 判定：可行
- 回归 v2 已就绪；v3 仅需叠加 D7（TTS mock）/D8（网络）两支。runbook 为当日产物（现未建，正常）。
- lab server 五天死 3 次均重启即愈，regression 已自动拉起——降为已知项。

### D11 · 真机点亮 —— 判定：可行，风险 中→低中
- 原"前端首启白屏"类风险已在 lab 反复消灭；问题域收窄为 ArkWeb 行为三件（拦截时机/proxy/CSP），预案 A/B 有效。
- **复检发现的未清偿缺口（A1，D11 前必须）**：设备端 RawFileServer 未处理 `/asset/<encoded>` 封面路径前缀（CENSUS D4 记录在案未实现）——不修则真机封面全挂，且同类 img 挂起会拖慢首屏（lab 已实证该模式可挂死 hydration）。

### D12 · 读完一本书 —— 判定：可行
- 全链每一环均有 lab 实证等价物 + 设备端代码：picker→copy_file→rangefile→foliate→relationalStore（标记文件）→进度恢复。
- 真机独有变量仅剩 content:// URI（已并入 A2）与 fetch/Blob 在 ArkWeb 的实测（窗口内攻坚，预案 B 兜底）。

### D13 · 命令核销 / D14 · 矩阵+性能 / D15 · 交付 —— 判定：可行
- D13：census 三态清单即核对表；TTS 锁屏续读为窗口内深层项。
- D14：语料 5 本就绪但**缺 mobi/azw3/pdf 样本（A4）**；pdf.js 主线程模式可在缓冲日先做 **lab 预验（A3）**降风险。
- D15：文档四件套按日累积；用户到场 30min 不变。

## 3. 行动调整建议（复检产出）

| # | 行动 | 归属 | 理由 |
|---|---|---|---|
| A1 | RawFileServer 补 `/asset/<encoded>` 前缀剥离 | D6–D7 清偿，**D11 前必须** | 封面路径；img 挂死模式 lab 已实证 |
| A2 | content:// URI 拷贝路径（SAF picker）对齐 | D7 实现清单 | D12 全链的真机独有变量 |
| A3 | 公版 PDF 在 lab 预开一轮（Worker=undefined 下 pdf.js） | 缓冲日 | D14 矩阵风险前置消解 |
| A4 | 语料补 mobi/azw3/pdf 公版样本 | D6–D10 任意 | D14 矩阵覆盖 |
| A5 | D6 提前至 10-17 执行 | 调度 | 决断越早，缓冲越多 |
| A6 | 死循环防护规则：无需修订 | — | 五天收敛统计全在预算内 |

## 4. 用户依赖清单（复核，无变化）
D11 插机+签名 55min ｜ D12–D14 验收点各 15–30min ｜ D15 发布签名 30min ｜ 可选模拟器账号登录。各项降级路径有效。

---

# 剩余六日可行性再评估（D10–D15）· 2026-10-20 D9.5 全量验证轮时点

> 依据：PLAN-15d.md × D6–D9 + 验证轮实证（回归 v2/v3、census 审计、模拟器 checkpoint、SelfTest 模拟器实跑）。
> 结论先行：**整体可行性上调**。原计划三大不确定源（模拟器、ArkWeb 集成层、命令核销面）中前两项已提前获得实证平台；六日均可行，无推翻性风险。D11 仍是唯一高不确定日，但其问题域已在模拟器上显影（KI-5），且新增"模拟器预攻坚"缓冲手段。

## 1. 形势对照（上次复检 D5 时点 vs 现在）

| 维度 | D5 复检时（10-16） | 现在（10-20 D9.5） |
|---|---|---|
| 进度 | D1-D5 完成（缓冲 +3 天） | D1-D9 + 验证轮完成；**D10 块A 的回归 v3 已提前做完**（http/tts/download_file 三断言绿） |
| 模拟器 | 未验证（账号依赖存疑） | **已可用资产**：镜像/实例/启动配方全通，未签名 HAP 直装，ArkWeb 双进程 + readest.local 加载实证，SelfTest 60/62 |
| 命令面 | 43/107 | **107+3 全归宿**；census 审计补掉 deep-link 缺口；GAP 清零（dialog 为观察项） |
| ArkWeb 集成层 | 全未知 | **模拟器上已显影**：UI 树渲染 ✓、前端 console 可经 hilog 观察 ✓、KI-5 TypeError 群 + file:// fetch 已归档为攻坚输入 |
| 回归 | v2 双 probe | v2 + v3 断言（7 个探针资产） |
| 风险清单 | 0 项 | KI-1/2/3/4/5/6 六项全有归宿日与预案 |

## 2. 逐日判定

### D10 · 总预演 —— 可行性：极高（当日剩余工作量小于一日）
- 已提前完成：回归 v3 三断言（http/tts/download_file）✓、全量 census 审计 ✓、风险清单复审 ✓。
- 剩余：①真机日 runbook 编写（每窗口操作清单+预期+失败分支——素材全在：SIGNING.md/check_device.sh/deploy.sh/observe.sh/KI 清单）；②hap 候选版冻结（git tag）；③**编译零警告复查**——当前 WARN≈58 条（NativeDatabase getContext deprecated 等存量），评估后豁免或消解（<1 天）。
- 判定：**可提前收工，溢出时间建议投入 D11 预攻坚**（见下）。

### D11 · 真机点亮 —— 可行性：中高（唯一高不确定日，但缓冲手段翻倍）
- 原风险：ArkWeb 拦截时机/proxy 注册/CSP 首次面对真机。
- **新增缓冲 1（模拟器预攻坚）**：建议 D10 溢出时间在模拟器上攻 KI-5（TypeError 群定位 + file:// fetch 修复方向验证）——模拟器与真机同为 ArkWeb 内核，问题域同构；预攻成果直接平移真机。
- **新增缓冲 2（观察通道）**：ARKWEB-CONSOLE hilog 通道 = 真机上的"lab __errors"，调试信息不再盲。
- 用户依赖 55min（插机+自动签名）不变，降级路径有效（未签名包继续观测准备）。
- 判定：**可行**。若首启攻坚超时，预案 B（本地 socket 加载）已在计划内。

### D12 · 读完一本书 —— 可行性：高
- 依赖 D11 修复平移；web 层开书链已七日绿（D4-D5 + 验证轮复验）；picker→沙箱拷贝→渲染全链在 lab/SelfTest 双验。
- relationalStore 真实落盘 + 重启恢复为当日新验项，SelfTest 模拟器已跑过 DB 族命令（非 THROW）。

### D13 · 命令核销 —— 可行性：高
- SelfTest 62 用例真机一键触发（入口 `--ps selftest 1` 已就位）；模拟器 60/62 为基线预期。
- KI-1 Edge TTS 真网核销；失败则确认 native 降级（lab 已验证为可用路径）。相册 WRITE_IMAGEVIDEO user_grant 观察项一并核。

### D14 · 矩阵+性能 —— 可行性：高
- 语料 8 本就绪（EPUB×5/MOBI/PDF/中文 PDF 自制；azw3 候选）；pdf.js lab 预验 D6 已做（A3 清偿）。
- 性能三指标：冷启（模拟器可先测一轮）/翻页/内存——工具（hdc/snapshot/hilog）全通。

### D15 · 交付 —— 可行性：极高
- **git 仓库初始化已提前完成**（本轮，commit 2d7a2f4）；文档四件套按日累积中。
- 剩余：发布签名（用户 30min）→ release 构建 → 终验旅程。

## 3. 结论与建议

1. **六日全部可行，无需修订计划骨架**；进度领先 + 模拟器资产 = 双保险。
2. **唯一调度建议**：D10 溢出时间 → 模拟器预攻 KI-5（把 D11 的高不确定日风险前置消解）。
3. WARN 58 条处理原则：deprecated getContext 类豁免（记录）；真错误（如有）消解——D10 块内完成。
4. 用户依赖四项不变（55min + 3×15-30min + 30min ≈ 2.5h），全部有降级路径。

## D15 终态（2026-10-23）—— 真机窗口等价验收全绿

- **D11** 首启验收：KI5 探针全 true、首页稳定渲染、SelfTest 真机基线 60/64
- **D12** 端到端链路：导入（file:// want→NativeFile→copy→书库）→阅读→翻页→重启进度恢复（progress+epubcfi 落盘）全绿；四大根因修复（fs file-handle 协议组 +19 case / iframe getter 转发+全 shell 加固 / 缓存绕过 ?v=buildstamp / os_type windows）
- **D13** TTS HiAI 离线引擎真机朗读（init/check/speak→speakInner）+ 剪贴板
- **D14** 格式矩阵 10/10（EPUB×5 + MOBI + AZW3 + PDF + GBK TXT + 竖排 EPUB，竖排渲染截屏确认）
- **KI-7 关闭**：Clash 代理 TLS 拦截（环境），rport 明文 http 正常——非平台 bug
- **回归**：lab v3 七项 PASS + 真机 SelfTest 60/64+4SKIP
- **git**：9ce1ba6 → 3e1f085 → 3cb69bd（tag d13-d14-device-green）
- 遗留（后续增强，不阻塞交付）：热启动 want 在 reader 页落 pending 无 listener（冷启动正常）、沙箱 iframe（无 allow-same-origin）注入不可达（真 Tauri 同象）、Edge TTS 在线引擎（网络环境阻断）
