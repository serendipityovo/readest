# RUNBOOK.md — 真机日操作手册（D11–D15）· D10 总预演产出

> 每个窗口 = 步骤清单 + 预期结果 + 失败分支。所有命令以仓库根 `D:\Projects\ReadestOhos` 为 cwd。
> 通用工具：`hdc`（`/e/DevEco Studio/sdk/default/openharmony/toolchains/hdc`）；日志通道 `hilog | grep -E "ARKWEB-CONSOLE|JSAPP|readestD9"`（前端 console 全量）；截图 `hdc shell snapshot_display -f /data/local/tmp/x.jpeg` + `MSYS2_ARG_CONV_EXCL="*" hdc file recv`。
> 全局降级原则（计划规则5）：用户不在场时一切验收点改自动判定 + 记录待复验，绝不阻塞。

## 窗口 0（任意真机日前夜，无人值守可做）· 模拟器预攻坚

1. 启动模拟器（配方见 PROGRESS D8 条目）→ 装最新 hap → `aa start` 普通启动。
2. 预期：UI 树根 = `readest.local/index.html`，截图像素非空白。
3. 抓首启 1–2s 窗口的 ARKWEB-CONSOLE 日志 → 定位 KI-5 TypeError 群的准确 chunk 与调用序。
4. 失败分支：模拟器起不来（tconn 15555）→ 直接转 D11 真机做，不阻塞。

---

## D11 · 点亮（用户到场 55 分钟：插机 + 签名）

### A. 插机与授权（用户，~10min）
1. 手机插 USB、保持亮屏；弹"允许 USB 调试"→ 勾选一律允许。
2. 验证：`hdc list targets` 出现设备序列号。
   - 失败：换线/换口 → 开发者选项里"重置 USB 调试" → 仍失败则启用无线调试（设置→开发者选项→无线调试，`hdc tconn IP:port`）。

### B. 自动签名（用户，~15min；详见 SIGNING.md）
1. DevEco Studio 打开工程 → File → Project Structure → Signing Configs → 勾选 Automatically generate signature → 华为账号登录确认。
2. 验证：Signing Configs 出现 debug 证书无红字；`build-profile.json5` 的 signingConfigs 非 `[]`。
   - 失败：账号问题 → 记录，改用命令行手工证书（`tools/hvigor` 支持本地自签 debug）或继续未签名包做观测准备（模拟器已证未签名可装——真机需签名，此项失败则当日转模拟器攻坚 + 次日重试签名）。

### C. 设备版本检查（自动，~2min）
1. `bash scripts/check_device.sh`。
2. 预期：API ≥ 26（targetSdk 26.0.0）。
   - 失败（API < 26）：触发**预案 A**——`build-profile.json5` 降 `compatibleSdkVersion` 到设备版本后重编（前端/桥层无 API 26 强依赖，降级面 = compileSdk 相关 Kit 差异，逐条编译暴露）。

### D. 签名构建装机（自动，~5min）
1. `bash scripts/deploy.sh`（构建→安装→启动一条龙）。
2. 预期：`AppMod finish` + `start ability successfully`。
   - 失败：安装报错 9568289（签名不匹配）→ 卸载旧包重装；`hdc install` 失败 → 查 `bm dump -n com.readest.app`。

### E. 冒烟页验桥（自动，~3min）
1. `aa start -b com.readest.app -a EntryAbility --ps selftest 1` → 等 90s → dumpLayout。
2. 预期：summary 含 `60/62` 或更好（基线 = 模拟器实测 60/62 + 2 SKIP）。
   - 失败：逐组看 THROW 条目 → 对照 COMMANDS.md 契约修；TTS 组 THROW → KI-1 范畴。

### F. 真实前端首启攻坚（自动+在场，剩余窗口时间，硬目标 17:30）
1. 普通启动 app，观察首页；抓全程 hilog。
2. 预期：首页稳定渲染（书库空态 + 导入按钮）。
3. 已知问题域（KI-5，模拟器已显影）：
   - 首启 1–2s TypeError 群（invoke/os_type/metadata undefined）→ 若首页最终渲染成功则为良性噪音，记录即可；若白屏 → 按 hilog 逐条攻：shim 注入时序（index.html script 顺序）/ RawFileServer 拦截时机 / onInterceptRequest 返回头。
   - file:// fetch ERR_FAILED（文件导入链）→ 修法：RawFileServer 拦 `file://` 转沙箱 fs 读（onInterceptRequest 已有同构逻辑），或前端 importBook 改走桥 copy_uri_to_path 后用相对路径。
4. 失败分支（2 小时停靠规则）：**预案 B**——加载模式切本地 socket（ArkWeb setWebSocket / 自建 local server），代码侧双实现开关（计划规则6），不改业务代码。
5. 17:30 验收：**首页稳定渲染**。达成 → git commit 固化；未达成 → 停靠记录 KNOWN-ISSUES，次日窗口首攻。

### 窗口后（无人值守）
- 问题复盘 + 次日预修（模拟器复现路径验证）+ PROGRESS 更新。

---

## D12 · 读完一本书（验收点 15–30min）

1. 装当日构建（`scripts/deploy.sh`）。
2. 导入链：picker 选 `testcorpus/hongloumeng.epub`（adb 推到 Download 或文件管理器复制）→ 沙箱拷贝 → 书库出现。
   - 失败：picker 不弹 → 查 dialog|open census；`content://` 拷贝错 → copy_uri_to_path 的 uri 授权形态对齐（A2 行动项）。
3. 开书 → 翻 10 页（CJK 渲染/分页/目录抽查）。
   - 失败：白屏 → hilog ARKWEB-CONSOLE 看 foliate 报错；fetch convertFileSrc 失败 → RawFileServer 路由核查（lab 已绿，差异只在 ArkWeb 行为）。
4. 重启 app → 进度恢复在断点页。
   - 失败：relationalStore 落盘问题 → `bm dump` + SelfTest DB 组复跑。
5. 验收（用户 15–30min）：**中文 EPUB 读完十页 + 重启进度在**。
6. 同步抽检（可选，有账号）：登录 → 进度云端标记。

---

## D13 · 命令核销（验收点 15–30min）

1. SelfTest 全量（同 D11.E）→ 真机基线固化。
2. TTS 听书 10 分钟：锁屏续读 + 焦点切换恢复。
   - 默认引擎（Edge 真网）→ **KI-1 核销**；失败 → 确认 native 降级可用（lab 已证）并记录。
3. 剪贴板：阅读页复制引文 → 系统粘贴板验证。
4. 分享/对话框/深色跟随/亮度/常亮/方向：逐项手验（COMMANDS.md 🔬 项）。
5. 相册保存（KI 权限观察项）：保存封面 → 若弹 WRITE_IMAGEVIDEO 授权则允许并记录；无弹且失败 → 补动态申请代码。
6. 文件关联真机核验（D9 代码）：文件管理器点 epub → "打开方式"出现 Readest → 打开进书（KI-5 file:// 修复的端到端验证）。
7. 格式矩阵首轮：epub / mobi / pdf 三本各开一次。
8. 验收（用户 15–30min）：**听书 10 分钟 + 三种格式可开**。

---

## D14 · 矩阵与性能（验收点 15–30min）

1. 格式矩阵全量：7 格式 × 5 检查（打开/翻页/目录/搜索/进度恢复；语料 corpus 8 本 + GBK TXT 现制 + 竖排样本）。
   - pdf.js worker：主线程模式实测（可行则移除 Worker 预防线开关）。
   - azw3：样本缺 → 公版转换或标降级（记录，不阻塞交付）。
2. 性能三指标：
   - 冷启 <5s：`aa start` 起计时到首页渲染（hilog 首帧日志）。
   - 翻页流畅：大书（红楼梦）连续翻 30 页主观 + hilog 掉帧抽查。
   - 一小时内存平稳：后台挂一小时读书，`hidumper -s mem -p <pid>` 前后对比。
3. 定向优化（超时 2h 停靠规则）。
4. 验收（用户 15–30min）：**矩阵全绿 + 指标达标**；未达项记录 KNOWN-ISSUES 并给结论。

---

## D15 · 交付（用户 30 分钟）

1. 发布签名（用户）：AGC 发布证书（只自用则 debug 签名包亦可）。
   - 失败：debug 包交付 + 记录发布签名补做路径。
2. release 构建（`--mode module -p product=default` + release 配置）→ 终验：安装 → 导入 → 读完一本 → TTS → 同步抽检（完整旅程）。
3. 文档四件套定稿：BUILD.md（构建配方）/ ARCHITECTURE.md（已有，核对）/ COMMANDS.md / KNOWN-ISSUES.md。
4. git 终态提交 + tag `v1.0.0-d15`。
5. 缓冲吸收残余 → **交付**。

---

## 附：风险→窗口→预案编号总表（D10 冻结版）

| KI | 内容 | 归宿窗口 | 预案 |
|---|---|---|---|
| KI-1 | Edge TTS 真网不可达（lab 现象） | D13 | 失败即确认 native 降级（已 lab 验证） |
| KI-2 | lab 桌面宽度 mini player 隐藏 | D13 | 设备移动布局预期正常；仅观察 |
| KI-3 | mini-SQL 剩余不支持（lab-only） | 设备不受影响 | 无需动作；D10 复诊维持 |
| KI-4 | labfs localStorage 容量（lab-only） | 设备不受影响 | 无需动作 |
| KI-5 | 首启 TypeError 群 + file:// fetch | D11 窗口 F | 修法两路（RawFileServer 拦截 / 桥读取）；预案 B = socket 加载 |
| KI-6 | mock 大书 read_file 性能（lab-only） | 设备不受影响 | 无需动作；lab 大书场景换小书语料 |
| — | API < 26 设备 | D11 窗口 C | 预案 A：降 compatibleSdkVersion |
| — | 签名失败 | D11 窗口 B | 手工证书 / 未签名转模拟器攻坚 |
| — | azw3 语料缺 | D14 | 转换或标降级记录 |
