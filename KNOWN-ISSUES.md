# KNOWN-ISSUES.md — 停靠项与已知降级（死循环防护规则2/5）

> 状态：🟡停靠待复诊｜↘️明确降级（不阻塞交付）｜✅已解决归档

## 🟡 停靠/待复诊

### KI-1 Edge TTS 在线合成：lab 网络不可达 → D13 真机核销（D8 已实现代码）
- **状态更新（D8 块A）**：plugin:websocket 双端已实现（设备 @ohos.net.websocket 编译绿；lab 真 WS 透传 + 连接门控）；但 **lab 环境直连 api.msedgeservices.com 失败（WS close 1006）**——浏览器 WS 无法设 UA/Origin 头 + 网络可达性双重限制，属 lab-only
- **设备预期**：OHOS websocket API 可带自定义 header 且网络不受 CORS 限制
- **下一步**：D13 真机窗口用默认引擎（不设 preferredClient）触发朗读，核销 Edge 在线合成；失败则确认降级到 native（Core Speech Kit 已全通）
- **影响面**：仅在线音色（晓晓等）；native 链路已 lab 全通

### KI-2 lab 桌面宽度下 TTS 迷你播放条 opacity-0（D7 观察）
- lab IAB 1280px 走桌面布局，mini player 渲染但隐藏；朗读本体（推进/翻页/高亮）全通
- 设备为移动布局，预期正常显示；D13 真机观察，不阻塞

### KI-3 mini-SQL 剩余不支持：表别名 / JOIN / NOT EXISTS / GROUP BY / 顶层 SELECT 列子查询（lab-only）
- 受影响：TTS cache 状态查询（getSectionStatuses 的 NOT EXISTS 链）、median page duration 查询——均被前端 catch 降级（返回空集/回退估算），非致命
- 设备端 relationalStore 跑真 SQL，不受影响；D10 复评是否值得补 mock

### KI-4 labfs localStorage 容量（lab-only，D8 新增）
- OPDS 下载入库后每本书 ~1MB b64 存 localStorage（配额 ~5MB）；多本下载会逼近上限（quota 抛出时 saveFiles 静默吞错）
- 设备端无此问题（真实文件系统）；若 D9+ 需 lab 批量下载场景，换 IndexedDB 或探针前清理

### KI-5 首启 TypeError 群 + file:// 导入链（D10.5 预攻：主因已修，残余打包 D11）
- **已修（模拟器实证）**：①**dispatch 双命名风格统一**——42 个带 `plugin:native-bridge|` 前缀 case 与 27 个裸名 case 并存，裸名 case 对带前缀到达的命令**全部失配返回 null**，致首启 `null.available/null.height/null.error` TypeError 群（lab mock 用带前缀全名表所以 lab 零此象；SelfTest 的"非 THROW"判定掩盖 null 应答）。修复=dispatch 入口剥前缀 + 全部 case 统一裸名 → **首启 TypeError 群消零**（新进程 console 仅语言切换日志）②fsPath 剥 `file://` 前缀（importBook→NativeFile 路径）③index.html pre-script 兜底 `__TAURI_INTERNALS__.metadata`（防御性）
- **残余（D11 真机窗口攻，工具=DevEco webview devtools）**：①`Cannot read properties of undefined (reading 'metadata')`（堆栈 E=getCurrentWindow←subscribeSettingsSync 的 M）与 `reading 'os_type'`（app service init）**偶发于 onPageEnd 探针确认 internals 在位之后**——pre 兜底未治，疑似更早瞬态或另一上下文，hilog 拼图已到极限，devtools 现场调试优先②file:// SEND 导入未落盘（Open with book 后 metadata 错误中断 ingestFile 链）
- **观察工具**：`hilog | grep ARKWEB-CONSOLE`；Index.ets onPageEnd 已内置 [KI5] 全局探针 + unhandledrejection 堆栈探针（KI5-REJ）

### KI-7 download_file 对外网 https 不落盘（D12 关闭：设备网络环境）
- 现象：gutenberg / 清华镜像 https 在模拟器与真机均无响应；**rport 明文 http 到 PC 完全正常**（1.1MB 秒下）；系统 AppGallery 同报 cert 错误
- **结论**：<local-proxy> 代理 TLS 拦截——环境问题非平台 bug。看门狗已加（download_file 20s 超时 reject 防永挂）；发布环境（无代理/正常网络）预期正常
- SelfTest 网络组现状：fetch 用例 SKIP + download_file 用例（清华镜像 URL + 20s 看门狗）

### KI-5（D12 关闭主项）
- 双命名（D10.5 修复）+ iframe getter 转发 + 全 shell 加固 + 服务端 OS 兜底 + 缓存绕过（?v=buildstamp）——真机 REJ 群与 app service init 失败双清零
- 残余已知项：sandbox iframe（无 allow-same-origin）内的代码无法注入（跨域）——真 Tauri 同象，非阻断

### KI-6 mock read_file 大书性能（lab-only，D10 验证轮发现）

- 红楼梦 1.1MB EPUB 经 mock read_file 返回 ~4MB JSON 字节数组——reader 渲染超时，TTS 取句失败（metadata 更新后立即 stop，speak 从未发出）；Repro 小书全链正常
- 设备端 read_file 走真实 fs（无此问题）；lab 大书场景（>500KB）暂用小书语料，若需 lab 大书回归再优化 mock 传输（二进制直传替代 JSON 数组）
- 附带发现：**虚拟时间下 TTS 探针方法论**——长书朗读会无限消耗虚拟时间预算（dump-dom 不 settle），探针必须"达标即停"（再发 't' 关闭）；引擎探测链（Edge 失败→native init→首句）需 10s+ 窗口，过短的复查窗口会把已开启的播放误关

## ↘️ 明确降级（不阻塞，功能等价或有据可依）

| 项 | 降级语义 | 依据/备注 |
|---|---|---|
| localsend 局域网传书 | start 答 running-idle 状态（防管理器重启风暴，D4 实测 ×107）；无 mDNS/HTTP server | 完整实现列入后续增强；书籍导入另有 picker/下载/同步路径 |
| iap / icloud / boox 笔 / raw drawing / eink 刷新 / 服务卡片 / carplay / lookup 词典原生壳 | 契约形状正确的功能性空应答 | 华为生态等价物（IAP→华为 IAP、卡片→服务卡片）为发布后增强 |
| auth_with_custom_tab/safari | {success:false} | 登录走系统浏览器（D9 want 处理同源推进；邮箱密码路径 D8 已真网验证） |
| TTS 播控中心（media session） | update_* 为 void no-op | 锁屏播控 D13 真机观察后定增强方案 |
| playout_enqueue/control | null | 直读引擎（Core Speech Kit）无媒体时钟，前端已适配 {position:0} |

## ✅ 已解决归档（D7）

| 项 | 解法 |
|---|---|
| Channel index=0 重复被吞（朗读一句卡死） | 双端 per-Channel 单调 index；设备改广播+按 channelId 移除（NativeBridge.ets emitChannel） |
| labChannelSeq 作用域（每命令重置） | 提升为页面级全局 |
| statistics.db 写链全断（DO NOTHING/多行 upsert/max()/标量子查询不支持） | mini-SQL 五项扩展，实测数值全对 |
| updateStmt 正则在子查询内 WHERE 处截断 SET 子句 | 括号感知扫描替代正则切分 |
| 设备端 localsend_start null → 重启风暴风险 | 补 4 case 空闲语义 |
| 设备端 clipboard write_text 无实现 | pasteboard 实现 |

## ✅ 已解决归档（D8）

| 项 | 解法 |
|---|---|
| fetch_read_body 哨兵实现错误（数据随哨兵 1 被丢弃，res.text() 恒空） | 双端改「chunk+[0] 续流；裸 [1] 结束」（源码核验 commands.rs），OPDS feed 解析复活 |
| X-Proxy-Headers '\n' 拼接非法头值（2+ 请求头即 fetch "Invalid value"） | JSON 数组 [[k,v],...] 传输，lab_server 双格式兼容 |
| download_file 双端缺失（OPDS 点下载即失败） | 设备 @ohos.net.http + fsWriteBytes + deliverDirect 进度；lab /__proxy + labfs 二进制；端到端入库 PASS |
| 不可达 URL 走 status 0 envelope → dist-js Response 构造抛裸 TypeError | mock 层 status 0 直接 reject（对齐设备 BusinessError 口径），错误视图文案可读 |
| 回归语言漂移（headless Edge 系统 en 覆盖 zh，'第1页' 断言挂） | probe_reader 种子强制 globalViewSettings.uiLanguage + i18nextLng = zh-CN |
| 模拟器中文用户名路径 qemu 打不开 system.img | 镜像/实例迁 D:/emu-image、D:/emu-inst（imageRoot 下需 system-image/ 层级），-imageRoot/-instancePath 显式传参 |

### 非缺陷备案：红楼梦语料源级缺字（2026-10-24 诊断闭环）
- 现象：第 69 页"加以麟髓之醅，**鳳乳之□釀**"等处出现方框，用户感知为渲染缺字
- 诊断（三层排除后定位）：①字体链无缺失（canvas 逐字 800+ 繁简字符零豆腐，含 醅/麴/麟/髓/鳳 等全部罕见字）②DOM 单一字体链 ③高清放大截图该行无渲染异常
- **真因：epub 源文本字面量 U+25A1（WHITE SQUARE）**——Gutenberg 版红楼梦在电子化时丢失 367 个罕见字（如 麴），以 □ 替代写进了书文件本身。上游 readest 桌面版/任何阅读器打开此文件显示相同
- 处置：非应用缺陷，不改代码。如需完美文本可换其他版本语料（如人文社排版电子书）

### 非缺陷备案②：Gutenberg 红楼梦语料的格式特征（2026-10-24 追查）
用户感知的三类"异常"均为书源文件自带，任何重排阅读器同样显示：
1. **段中莫名空格**：源文本段内含 **24052 个硬换行**（429 段中 276 段有）——Gutenberg 当年按固定宽度断行灌入 epub，重排后每个换行折叠成一个空格（例："暫不能寫矣．如⏎今且說"→"寫矣． 如今且說"）；另有 4684 个全角空格（U+3000，标题分隔等）
2. **标题下"下划线"**：实为 **U+2014 破折号连排 ×4338**（Gutenberg 装饰分隔线）；实测字形纵向居中（dash mid 49px vs 汉字 mid 47px @48px），非贴底下划线
3. **标点风格**：全书用全角逗号"，"替代顿号"、"、全角句点"．"——源排版风格
处置：语料侧特征，应用零修改；追求完美文本请换其他版本电子书

### 非缺陷备案③：正文"破折号"实为下划线字符（2026-10-24 · 页32 现场取证）
- 现象：用户读第 32 页"黛玉方拜見了外祖母——此即冷子興所云之賈氏太君"，感知中间是下划线
- **取证（DOM）**：源文本字节为 `拜見了外祖母．____此即…`——原书破折号（——）被 Gutenberg 电子化时转写为 **4 个 ASCII 下划线 `____`（U+005F）**；全书 101 个下划线均属此类转换痕迹
- 结论：用户感知完全正确（字形就是下划线）；属语料源级转写，非渲染缺陷（同前两条同源：Gutenberg 电子化质量）
- 区分：章标题下的长横线是真破折号连排（U+2014×4338，备案②）；句中"破折号"是下划线转写（本条）

### 非缺陷备案④：书架"丢书"= 桌面版 transient 导入语义（2026-10-25 破案）
- 现象：真机书架空，但 Books/<hash> 目录在、书可正常打开阅读
- 机制（bundle ingestFile 取证）：桌面语义下（os_type=windows），`transient = !isMobile && !autoImportBooksOnOpen`——**"打开时自动导入书籍"关闭时，file-association/want 打开的书按 transient 导入**（`deletedAt` 立即置位）：能读、有进度/书签/高亮，但**不进书架**。与上游桌面 readest 行为逐位一致
- 处置：非缺陷。需要 want/双击打开永久入库 → 设置开启"打开时自动导入书籍"；或用导入按钮/picker 导入（非 transient）
- 关联：删除书籍的 deletedAt 机制同链路（C 项验证时顺带证实标记机制工作正常）

### 安全审计加固记录（2026-10-25 最苛刻复查）
**发现**：①RawFileServer `/asset/` 通道接受任意绝对路径（同源恶意书内容可拉取 settings.json 等沙箱敏感文件——上游 Tauri asset 协议有 scope 白名单，此前未复刻）②桥接 fs 命令（read/write/copy/rename/download/open）对绝对路径无域约束
**加固**：①`/asset/` 收窄到 filesDir/cacheDir 前缀（403 其余）②NativeBridge 中央 `assertSandboxPath` 钳制（fsPath/copy_file/rename/download_file/fs|open 五路出口）
**验证**：攻击负向测试 3/3 拦截（沙箱外读 BLOCKED/写 BLOCKED/asset 越权 BLOCKED）；合法链零误拒（导入 open×48 绿、零 sandbox 拒绝）；SelfTest 60/64+4SKIP 零回归
**残留面（与上游等价、记录在案）**：沙箱内文件对同源书内容仍可读（上游 appdata scope 同语义）；debug 构建含 webview 调试通道（发布流程 sed 关闭，PUBLISH.md）

### 环境备案（2026-10-25 深夜 · 最终核验轮）
- 现象：regression_v3 批量调用下 boot/reader 探针间歇 FAIL，伴随无头 Edge **段错误**（进程级崩溃）
- 仲裁：同代码手工串行双探针（新 profile）**全 PASS**；今晨同代码 v3 7/7——**应用代码健康，属连跑 3 天重载后 Edge/系统环境劣化**
- 处置：v3 boot 步骤已加一次重试（对齐 probe_with_retry 抖动语义）；建议整机重启后复跑 v3 预期恢复 7/7
