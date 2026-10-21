# PROGRESS.md — 每日块C更新（死循环防护规则8）

## D10.5 · 2026-10-21（无真机工作清尾）—— KI-5 预攻重大战果 + 四项准备物补齐

### ① KI-5 预攻（RUNBOOK 窗口 0，模拟器）
- **根因抓到并修复：dispatch 双命名风格**——42 个带 `plugin:native-bridge|` 前缀 case 与 27 个裸名 case 并存，裸名 case 对带前缀到达的命令**全部失配返回 null** → 首启 `null.available/null.height/null.error` TypeError 群（lab mock 用带前缀全名表所以 lab 零此象；**SelfTest 的"非 THROW"判定掩盖了 null 应答**——null 也是非 THROW）。修复=dispatch 入口剥前缀 + 43 个 case 统一裸名 → **首启 TypeError 群消零**（新进程 console 仅语言日志，模拟器实证）
- 顺带修复：fsPath 剥 `file://` 前缀（importBook→NativeFile 链）；index.html 注入 `__TAURI_INTERNALS__.metadata` pre-script 兜底（package_frontend.sh 增）
- 诊断工具沉淀：NativeBridge invoke/dispatch/resolve 三级 hilog 打点（readestD9 域）+ Index.ets onPageEnd 探针（[KI5] 全局形状 + [KI5-REJ] unhandledrejection 堆栈）——**hilog 拼图法把根因从"疑似 ArkWeb 时序"收敛到"纯命名 bug"**
- **残余停靠（两小时规则）**：`metadata/os_type` 瞬态 undefined（onPageEnd 探针确认 internals 在位后仍偶发；pre 兜底未治；堆栈定位到 getCurrentWindow←subscribeSettingsSync）+ file:// SEND 导入未落盘——打包 D11 真机（工具升级：DevEco webview devtools 现场调试）
- SelfTest 复跑 60/62 → 统一修复**零破坏**

### ② BUILD.md（D15 文档四件套补缺）
九节全量构建配方：前端构建→打包（含 KI-5 pre-script 注入）→HAP 构建（警告基线 54 豁免）→装机→一条龙→签名→实验室→模拟器→常见坑（含 git rm 参数序、lab SSL 重启、增量构建警告盲区）

### ③ D14 语料补齐
GBK TXT（王国维三境界，349B GBK 编码）+ 竖排 EPUB（writing-mode:vertical-rl，日文+中文，1.9KB）自制；**azw3_sample.azw3 发现早已有**（D6 448KB）——语料库 10 本全格式

### ④ 模拟器冷启预测 + 网络组增补
- **冷启 PASS**：force-stop→首帧 1.0s→前端就绪 3.2s（<5s 达标线；hilog 时间戳法）
- **SelfTest 增网络组**（64 用例）：plugin:http|fetch（SKIP：rid 接力说明）+ download_file（gutenberg 真网真写盘）
- **KI-7 新档**：模拟器 @ohos.net.http 对外网 https **挂起**（ping/DNS 通、ArkWeb 栈通、仅系统 http API 挂；嫌疑模拟器 CA/TLS 环境）——D11 真机重验，非代码问题（lab 逻辑全验证）

### 回归
- lab 回归 v3 七项全 PASS（全部改动后零回归）
- 模拟器 SelfTest 60/64 非 THROW + 3 SKIP

### 给 D11 的输入（更新）
- **首启攻坚重点转移**：TypeError 群已修——D11 剩 metadata/os_type 瞬态 + file:// 落盘 + 真机网络组重验（KI-7）——全部有 devtools 现场调试手段
- SelfTest 已扩到 64 用例（真机基线预期 ≥60）

## D10 · 2026-10-20（块A/B/C 全部完成）—— 总预演：web 层冻结 + runbook 就绪 + 候选 tag

### 块A：回归 v3 全绿，web 层冻结（D9.5 已提前三断言，本日补总脚本）
- **scripts/regression_v3.sh**：串联 7 探针（boot/reader/turso/opds_fail/http/tts/opds），真网探针带 1 次重试，结果入 .shots/regression.log
- **七项全 PASS**：`[boot][reader][turso][opds_fail][http][tts][opds]`——lab 验证体系（70% 工作量层）正式冻结；后续仅真机回归不再改 web 层

### 块B：WARN 处置 + runbook + 候选冻结
- **ArkTS 编译警告复查**（clean 全量清单）：57→54 条——3 条 `getContext deprecated` **已消解**（`this.getUIContext().getHostContext()`，Index×2 + SelfTest）；剩余 54 条豁免并记录：53 条 "Function may throw"（捕获边界统一在 invoke→reject 前端，语义正确）+ 1 条 WRITE_IMAGEVIDEO（user_grant 可选权限，D13 观察项）
- **docs/RUNBOOK.md**（真机日手册，核心产物）：D11-D15 每窗口步骤+预期+失败分支全落——含模拟器预攻坚窗口 0、D11 六段流程（插机/签名/版本检查/装机/冒烟/首启攻坚+预案 B socket）、D12 导入链+进度恢复、D13 SelfTest 基线+TTS 锁屏+文件关联端到端、D14 矩阵+三指标、D15 终验+文档定稿
- **hap 候选版冻结**：git tag `candidate-d10`（提交链 2d7a2f4→4305344→5ffacd1→edc47d1）；.gitignore 补排除 .hvigor 构建缓存

### 块C：风险清单冻结 + 停靠复诊（完成）
- 风险→窗口→预案编号总表（RUNBOOK 附表，冻结版）：KI-1→D13（native 降级预案）、KI-2→D13（观察）、KI-3/KI-4/KI-6→设备不受影响（维持）、KI-5→D11 窗口F（双修法+预案B）、API<26→预案A、签名失败→手工证书/模拟器接力、azw3 缺→D14 转换或降级记录
- 停靠项复诊：无新增停靠；KI-2/KI-3 维持降级判定（设备端不受影响的 lab-only 项）
- 无三振；块B runbook 编写一次成型

### 里程碑达成
✅ 真机日 runbook 就绪 ✅ 风险清单冻结 ✅ web 层全绿冻结 ✅ 候选版 tag——**D11 起进入真机窗口期**

### 给 D11 的输入
- 先跑 RUNBOOK 窗口 0（模拟器预攻 KI-5）再进用户到场段
- 用户到场 55 分钟流程：插机(10) → 签名(15) → 版本检查(2) → 装机(5) → 冒烟(3) → 剩余攻坚
- 观察通道：`hilog | grep -E "ARKWEB-CONSOLE|JSAPP"`；SelfTest 入口 `--ps selftest 1`

## D9.5 · 2026-10-20（全量验证轮）—— D1-D9 盘点：v3 断言三绿 + census 审计补 1 缺口

### 验证内容（用户指令：全部内容和功能验证、查遗漏）
- **计划对照**：D1-D9 九天里程碑逐项核（PROGRESS 各日条目 vs PLAN-15d 验收点）——全部达成，无欠账
- **回归 v3 三断言全绿**（新探针 probe_http / probe_tts，download_file 沿用 probe_opds）：
  ① HTTP-PROBE-PASS：plugin:http 真网 gutenberg 200 / 8630B / 13 响应头 / 哨兵两段式读body ✓（顺带修 lab_server 老进程 SSL 暂时性失败——重启即愈）
  ② TTS-PROBE-PASS：native 引擎 3→4 句连续 speak + set_voice/media_session 链 + 干净停机（探针三轮迭代：虚拟时间下必须"达标即停"，否则长书朗读无限消耗预算导致 dump 不 settle）
  ③ download_file 入库：D8 OPDS-PROBE-PASS 沿用 ✓
- **census 全量审计**（probe_census：开书会话 32 命令清单）→ **发现并补掉唯一缺口 `plugin:deep-link|get_current`**（开书会话实测被调 ×3，双端此前皆无实现）：设备端返回 handleWant 首记录的启动 uri（string[]，与 shared-intent 双通道并存，前端 markLaunchUrl 去重 #6104）；lab 返回 []。编译门绿 + mock 同步
- **mock 顺带修复**：Edge TTS 域名（msedgeservices）websocket connect 快速失败——TTSController 引擎探测不再空烧 15s 超时（lab 语义对齐"网络不可达立即失败"）
- **回归 v2 复跑 PASS**（全部审计改动后零回归）
- 功能面扫描结论：核心链（书库/开书/翻页/标注/搜索/TTS/OPDS/登录/下载/文件关联/设置）全验证；UI 细分面（词典弹窗/翻译/标注导出 UI/字体管理页）依赖命令均已在清单内且桥已通，属 D12-D14 真机观察项非缺口
- **D11-15 准备物齐备**：SIGNING.md（55min 操作清单）/ scripts/check_device.sh + deploy.sh + observe.sh / KNOWN-ISSUES 风险清单（KI-1/2/3/4/5/6）/ 文档六件套；**唯一欠账 = D10 正日任务：真机日 runbook 编写 + hap 候选冻结**

### 新增观察项
- **KI-6 大书 mock read_file 性能**：1.1MB EPUB → ~4MB JSON 字节数组 → 渲染超时 TTS 取句失败（小书全通；设备端真实 fs 无此问题）

## D9 · 2026-10-20（块A/B/C 全部完成）—— 系统入口与外观：文件关联 + 品牌外观 + SelfTest 模拟器实跑

### 块A：文件关联全链（编译门绿 ×4）
- **module.json5 UTD 声明**：7 类型（general.epub / com.amazon.mobi / com.amazon.azw / com.amazon.azw3 / com.adobe.pdf / general.plain-text / general.ebook 兜底），skills 加 `ohos.want.action.viewData` + `scheme:"file"` + `launchType singleton`。**schema 两个坑**：①uris 必须带 scheme 字段 ②**maxFileNumber 是非法属性**（那是 fileSelect 场景的）——纯 scheme+utd 即合法
- **EntryAbility**：onCreate + onNewWant → nativeBridge.handleWant(want)；UIAbility 基类自带 `launchWant`（不可 private 重定义，直接用）；调试入口 `--ps selftest 1` → loadContent('pages/SelfTest')（D11 冒烟复用）
- **NativeBridge.handleWant**：file:// uri → {urls:[uri], action:VIEW|SEND}（sendData→SEND）；5 秒窗口去重；**热启动直接广播 / 冷启动 pendingIntent 暂存 + register_listener('shared-intent') 到达瞬间补投**
- **hilog 实证补投链全通**：`shared-intent replay from pending: file:///data/local/tmp/xiyouji.epub` → 1 秒后前端 console `Open with book: /data/local/tmp/xiyouji.epub`——want→暂存→补投→useOpenWithBooks 消费全链闭合
- 导入落盘卡在 `file:// fetch ERR_FAILED`（ArkWeb 对 file:// 的 fetch 限制）——属 D11"真实前端首启攻坚"预定问题域，记录 KI-5 不深挖（两小时停靠规则）
- **工具级发现：前端 console 可从 hilog 观察**（`A01194/ARKWEB-CONSOLE` + `A03d00/JSAPP` 标签）——模拟器/真机的 web 层日志通道，替代 lab 才有的 __errors

### 块B：外观 + SelfTest 模拟器实跑（全部完成）
- **品牌双层图标**：DevEco 默认模板 → readest 品牌设计（采样书本色谱：主体米黄 255,243,182 / 暗部深棕 95,44,32）——background 纯深棕 #5F2C20 + foreground 书本 62% 居中；startWindowIcon 合成图 70%；**启动画面底色像素实证**（冷启 0.4s 帧 avg(98,48,36)≈#5F2C20 ✓，3.4s 帧前端浅色首页 ✓）
- 深色跟随：onCreate COLOR_MODE_NOT_SET + dark/ 限定词资源 ✓；权限最小化复查：**INTERNET 单权限维持最小集**（传感器 AMBIENT_LIGHT 无权限注解、粘贴板写免权限、picker/want 授权路径免权限；save_image_to_gallery 的 WRITE_IMAGEVIDEO 为 user_grant 可选项，不加静态声明 → D13 观察项）
- **SelfTest 模拟器实跑：60/62 条非 THROW + 2 条 SKIP（交互类），零 THROW**——62 用例在 HarmonyOS 7.0.0 x86 模拟器全部执行，返回真实系统值（colorScheme=dark、状态栏 117、safeAreaInsets、ArkWeb-5.x、TTS init、turso、fs、http 全过）
- SelfTest 修补：picker 类用例（show_file_picker/select_directory）**弹系统选择器阻塞整页**——加 skip 机制（TestCase.skip 字段 + SKIP 计数进 summary）
- 模拟器操作配方沉淀：锁屏解锁 `power-shell wakeup` + `uinput -T -m 660 2100 660 200 120` 上滑；hdc 断连 `tconn 127.0.0.1:15555` 修复；**Emulator.exe -start 必须后台常驻跑**（前台 timeout 会连带杀掉模拟器）

### 块C：多语言 + 回归 + 归档（完成）
- 多语言核验：壳层字符串从模板占位改为实际描述（base en + zh_CN 限定词目录；label 保持品牌名 Readest 不译）；应用内多语言由前端 i18n 负责（zh-CN/zh-TW/en 全量 locales 已在 frontend 包，模拟器实测 Language changed to zh-CN 跟随系统 ✓）
- 回归 v2 双 PASS（D9 纯设备端改动，lab 侧零改动零回归）
- 编译门累计 ×4 绿（UTD schema 修复 ×2、SelfTest skip 机制、hilog 插桩、多语言资源）

### 停靠
- 无三振。file:// fetch 导入路径按预定归入 D11 攻坚域（计划原文："真实前端首启攻坚（问题域只剩 ArkWeb 行为：拦截时机/proxy 注册/CSP——预案B本地 socket）"）

### 风险/次日输入（给 D10 总预演日）
- **D10 块A 全回归 v3** 需新增断言：native 朗读 30s≥6 句（__census）、http fetch 真网 200、download_file 入库（probe_opds 已具雏形）
- **KI-5 新档**：模拟器首启前端早期 TypeError 群（invoke/os_type/metadata undefined ×5+，启动 1-2s 窗口内）+ file:// fetch ERR_FAILED——D11 攻坚输入；观察工具用 ARKWEB-CONSOLE hilog 通道
- 模拟器保留已停机；启动配方在 D8 条目（Emulator.exe -start phone26 -instancePath D:/emu-inst -imageRoot D:/emu-image -hdcport 15555）

## D8 · 2026-10-21/22（块A/B/C 全部完成）—— 网络层 + OPDS 下载入库端到端 + 模拟器首启

### 块A：网络命令族（编译门绿灯 ×2）
- **plugin:websocket 设备端**（@ohos.net.websocket）：connect（onMessage 直通道解析 + header 透传 + await open 门控）→ wsId；send（Text/Binary/Close）；消息经 deliverDirect 单调 index 投递（与 emitChannel 同序契约）；Device 端 Edge TTS 通道就位
- **plugin:websocket lab mock**：真实浏览器 WS 透传；连接建立后才 resolve（修竞态：过早 resolve → 客户端在 CONNECTING 期 send → InvalidStateError 重连环）；**Edge 端点 api.msedgeservices.com lab 直连 1006（网络环境不可达）→ D13 真机核销**
- **plugin:http 双端**：设备端 @ohos.net.http 实现 RID 协议（fetch→fetch_send→fetch_read_body 尾哨兵）；lab 端经 lab_server `/__proxy` 同源代理绕 CORS（设备无 CORS，纯 lab 现象）
- ArkTS 严格模式收敛：WsTextMessage/WsBinaryMessage/WsCloseMessage/PluginHttpResponse 显式 interface；util.TextEncoder 替代（无全局 TextEncoder）

### 块B：登录真网 + OPDS 下载入库 + 模拟器 checkpoint（全部完成）
- **登录真网链路 ✓**：/auth 假凭据提交 → 真实 Supabase 返回 "Invalid login credentials" 优雅呈现（邮箱密码路径 lab/设备同源）
- **download_file 双端补实现**（OPDS 书籍下载唯一缺口：tauriDownload→invoke('download_file')，此前双端皆无）：设备端 @ohos.net.http 单请求缓冲 + fsWriteBytes + deliverDirect 进度 + 响应头 Record 返回（Rust transfer_file.rs 契约）；lab mock 经 /__proxy + labfs {__b64} 二进制落盘；编译门 BUILD SUCCESSFUL
- **fetch_read_body 哨兵契约修正（双端真 bug）**：正确契约是「每次返回 chunk+[0] 续流；流结束的下一调用返回裸 [1]」——dist-js readChunk 对 lastByte===1 只 close 不 enqueue，**伴随哨兵 1 的数据被整块丢弃**（此前实现 bytes.concat([1]) 导致 res.text() 恒为空、OPDS 报"内容既不是有效的 XML 也不是 JSON"）。源码核验：tauri-plugin-http commands.rs（chunk.push(0) / vec![1]）
- **X-Proxy-Headers 多头修复**：'\n' 拼接的请求头值是非法 fetch header value（2+ 头触发 "Invalid value"）→ 改 JSON 数组 [[k,v],...] 传输，lab_server 兼容两种格式
- **OPDS-PROBE-PASS（lab 端到端全链）**：probe_opds.html 同源 iframe 驱动真实 UI：/opds?url=gutenberg → 点 Popular → 点 Pride and Prejudice → 点 Download EPUB → **library.json 1→2 本（新 hash 7b1de93d…）、EPUB 二进制落盘 Books/<hash>/、search.db 经 turso|batch 写入**；重跑验证幂等路径（已入库 → Download Again/Open & Read）。gutenberg 目录结构发现：搜索列表的内联 entry 无 acquisition links（仅 subsection），书本包在中间层 feed（/ebooks/N.opds 是 <feed> 非 <entry>）→ 需两层下钻
- **模拟器 checkpoint ✓（无华为账号依赖）**：devecocli 1.3.5 license accept（CI 非交互方式）→ 镜像 HarmonyOS 7.0.0(26.0.0) phone x86 2.09GB 下载 → **中文用户名路径 qemu 打不开 system.img（err 88000101 签名/路径链）→ 镜像迁 D:/emu-image（注意 imageRoot 下还需 system-image/ 层级）、实例 D:/emu-inst** → WHPX 加速冷启动 → **未签名 HAP 直接安装成功 → EntryAbility 启动 → 主进程 + :render（ArkWeb）双进程 → UI 树根 = http://readest.local/index.html（前端已加载）→ 截图像素统计非空白**。启动配方：`Emulator.exe -start phone26 -instancePath D:/emu-inst -imageRoot D:/emu-image -hdcport 15555`（hdc list targets → 127.0.0.1:15555）
- 登录 OAuth 深链（auth_with_custom_tab 系统浏览器）仍留 D9 want 处理同源推进

### 块C：失败路径 + 回归 + 归档（完成）
- **弱网/断网失败路径 PASS**（probe_opds_fail.html）：不可达 URL（127.0.0.1:9）→ **mock 层 status 0 直接 reject**（对齐设备端 ArkTS http BusinessError 口径，避免 dist-js new Response({status:0}) 抛裸 TypeError）→ 前端渲染 "Cannot Load Page" 错误视图 + Reload 按钮，FATALS=none，无白屏
- **回归 v2 双 PASS**；修复两处回归稳定性问题：① UI 语言实际由 settings.globalViewSettings.uiLanguage + localStorage i18nextLng 控制（headless Edge 系统 en 会覆盖）→ probe_reader 种子强制 zh-CN；② OPDS 下载的残留书使 library 基数变化 → probe 判定兼容幂等场景
- 文档归档：COMMANDS.md +download_file 命令 + 哨兵契约勘误；KNOWN-ISSUES 更新

### 停靠
- 无三振/停靠。块B OPDS 调查 6 轮迭代收敛（census 截断误判 → X-Proxy-Headers → 哨兵契约 → figure 选择器 → card-title → 中间层 feed 下钻），方法论沉淀：同源 iframe 探针 + census/errors 快照 + dumpDom 分层诊断

### 风险/次日输入（给 D9）
- 模拟器已可复用（D11 前的预验证环境）：模拟器上 SelfTest.ets 62 用例可提前跑（aa start 进 SelfTest 页）
- Edge TTS（默认引擎）lab 不可达 → D13 真机；若不可达，preferredClient=native-tts 已验证为可用降级
- 回归 v3（D10）：+「native 朗读 30s ≥6 句」+「http fetch 真网 200」+「download_file 入库」断言（probe_opds 已具雏形）
- labfs localStorage 容量：每本 OPDS 书 ~1MB b64，多本下载逼近 5MB 配额（D9+ 若做批量下载需换 IndexedDB 或清理策略——设备端无此问题）

## D7 · 2026-10-21（块A/B/C 全部完成）—— 里程碑达成：系统集成命令批次全归宿 + 朗读链路 lab 端到端全通

### 块A：全量命令归宿 + ArkTS 实现（编译门绿灯）
- 盘点：59 native-bridge + 18 native-tts 全部归宿；NativeTts.ets（Core Speech Kit：createEngine/speak/setListener/listVoices，OHOS 语义 start→end 无句级 boundary）
- NativeBridge 大扩展：TTS 18 case、picker（DocumentViewPicker/FOLDER 模式）、相册（MediaAssetChangeRequest）、Asset Kit 密钥、AMBIENT_LIGHT 传感器、泛化 `|register_listener` 通道
- 顺带修 3 个存量契约 bug：get_system_color_scheme→{colorScheme}、get_sys_fonts_list→{fonts:Record}、get_sync_passphrase 真读 Asset
- ArkTS 严格模式 4 轮收敛（显式 interface 替代 as Record、JSON 往返转 Voice、ILLUMINANCE→AMBIENT_LIGHT 等）

### 块B：朗读调查链（本轮最大战果——三个真 bug，双端修复，全部 lab 实证）
1. **引擎选择真相**：readest 默认引擎 Edge（在线 websocket）优先于 native——lab mock 的 websocket 空应答导致 UI 永卡"朗读任务加载中"；native-tts 从未被选中。⇒ `localStorage.ttsPreferredVoices.preferredClient='native-tts'` 切原生验证；**设备端 plugin:websocket 列为 D8 GAP（@ohos.net.websocket）**
2. **Tauri v2 Channel 消息序（双端契约 bug）**：Channel 只投递 `index===nextIndex`，固定 index=0 时第二句的 start/end 被永久挂起 pending → 朗读一句后卡死。源码核验（@tauri-apps/api/core.js）+ lab 三轮实证。**修复双端**：mock pushChannel per-Channel 单调 index；设备 emitChannel 同改 + 多监听广播（channels: Map<string,number[]>）+ remove 按 channelId 精确移除
3. **mock seq 作用域 bug**：labChannelSeq 误置 answerCmd 局部 → 每命令重置 → 第二句事件 index 重复被吞；改页面级全局
- **终验**：原生朗读连续 30 秒 7+ 段落推进、自动翻页（48→51）、高亮覆盖层、时间线倒计时、暂停/恢复正常、干净停机
- mini-SQL 五项扩展（统计链修复）：多行 VALUES upsert、ON CONFLICT DO NOTHING、max()/min() 标量、算术、标量子查询、SUM/COUNT(DISTINCT)/AVG/MAX 聚合、excluded 语义（裸列=旧行）；statistics.db 写链全通（实测 SUM/DISTINCT/MAX(start+duration)/ORDER LIMIT 子查询数值全对）
- 补设备端：localsend 4 命令（防 D4 实测的 ×107 重启风暴）+ clipboard write_text（pasteboard）；hap 重建绿灯 ×3

### 块C：文档 + 自测 + 回归（完成）
- **docs/COMMANDS.md**：107 命令三态清单（✅/🔬98、↘️22、🟡2→D8），含 D7 契约发现四条
- **pages/SelfTest.ets**：62 用例一键触发显示 dispatch 真实返回值（D11 冒烟/D13 核销工具），路由已注册，编译绿
- **regression.sh v2 PASS**（boot + READER-PROBE）
- KNOWN-ISSUES.md 建档

### 停靠
- 无三振/停靠（块B 修复循环 7 轮内收敛；调查用了面包屑插桩法：bundle 打点 → 状态转移 → pending invoke 追踪 → 事件序核对，逐层定位）

### 风险/次日输入（给 D8 块A）
- **D8 首项：plugin:websocket**（@ohos.net.websocket）——Edge TTS 是 readest 默认引擎，不实现=默认朗读降级到 native；建议实现透传并 lab 复验 Edge 在线合成
- D8 网络日顺带：plugin:http|fetch（NetworkKit）、登录流程真网验证
- lab 桌面宽度下 TTS 迷你播放条 opacity-0（设备为移动布局，D13 真机观察即可）
- 回归 v2 未覆盖 TTS 循环（需 15s+ 观察），D10 回归 v3 补"native 朗读 30s ≥6 句"断言（可用 __census 计数）

## D6 · 2026-10-17（块A 完成）—— 解析层决断：B 计划定案

### D6 前置行动项（复检 A1-A4，全部落地）
- A1 设备端 /asset/<encoded> 封面前缀（构建绿）；A2 copy_uri_to_path 命令（{uri,dst}→{success,error}，构建绿）
- **A3 PDF lab 预开全通**：pdf.js fake-worker 主线程模式渲染中文 PDF——揪出两个跨端真 bug 并修复：① 打包链缺 vendor/pdfjs（package_frontend.sh 增补，hap 43.5MB）② .mjs MIME 双端修正
- A4 语料 8 本（EPUB×5+MOBI+AZW3 候选+中文 PDF 自制）；回归 v2 双 PASS

### 块A：cargo check 决断（数据）
- `--target aarch64-unknown-linux-ohos --no-default-features -p Readest`：**唯一错误 = glib-sys pkg-config 交叉失败**
- 依赖链逆向：tauri(fork)→muda(菜单库)→gtk→atk/glib/cairo 全家；OHOS sysroot 无 glib/gtk
- 穿透代价：改 fork cfg + ohos runtime + NAPI 绑定 + 长期补丁面 ≈ **≥3 天**
- B 计划等价性：五天 lab 已证前端+ArkTS 全覆盖（fs/turso/解析/PDF/搜索/标注/事件全绿），Rust 无不可替代残留
- **决断：B 计划**（ARCHITECTURE.md 定案，含重启条件记录）
- 环境注记：Clash 代理 7897 今日失联，直连可用（gutenberg 直连下载成功）；cargo offline 缓存 873 crates 足够

## D5 · 2026-10-16（块A/B/C 全部完成）—— 里程碑达成：设置/进度/标注/搜索 lab 全通

### 块A 完成（设置链路）
- 字号 36→64、行间距 71→1.9 经真实 UI 滑杆调整 → settings.json 落盘 → **重载后滑杆/值完整回显**（fontSize 存储键未定位但行为正确：跨重启保持）
- 进度链 D4 已证；书籍 config.json 结构实证：`{schemaVersion, viewSettings, searchConfig, booknotes[], progress[page,total], location:epubcfi}`

### 块B 完成（搜索/标注/笔记）
- **书内搜索**：侧栏搜索框真实键入"甄士隱" → 多结果+高亮摘录（120 回全文）→ **点击结果跳转落点正确**（主线程路径，Worker 预防线生效）
- **标注高亮**：CUA 真实拖选 → 选择菜单（划线/笔记/搜索/词典/翻译/朗读/校对+样式行+五色）→ 划线 → **booknotes[0] 落盘**（type:annotation/style:highlight/color:yellow/cfi/page）
- **笔记**：选段 → 笔记按钮 → 编辑器输入"好了歌注…" → 保存 → **booknotes[1].note 落盘**
- **重载回显**：黄色高亮"竟無人作主"在重启后页面上可见（45/1600 恢复）
- 交互方法论：选择菜单位置随选区浮动——**每次实时探测按钮坐标**再点击（硬编码坐标两轮失败后确立）

### 块C 完成（事件系统 + 回归 v2）
- **__deliverEvent 端到端**：向 shared-intent 通道（register_listener 的 __CHANNEL__:5）投递 `{urls:[西遊記.epub], action:'VIEW'}` → **书籍自动导入**（"文件管理器→用 Readest 打开"完整复刻，D9 文件关联前置验证）零错误
- **回归 v2**：+READER-PROBE（种子小书→/reader?ids→DOM 关键词 Repro+第1页）
- 修出的回归基建坑：① lab_check 预算 15s→30s；② **书库有书时封面 <img> 打 DNS 不存在的 readest.ohos.internal 会挂死 headless hydration**（纯 lab 现象，设备端有 RawFileServer 应答）→ boot 检查独立 profile（.edge-profile-boot）；③ probe 保留 settings.json 防首装初始化拖慢
- lab server 曾死（curl 000）→ lab_up.sh 重启即愈（第 3 次，工具层已知项）

### 给 D6（Rust 决断日）的输入
- cargo check 全量重跑（代理+PKG_CONFIG sysroot），cairo 链评估或 B 计划（foliate-js 等价命令 lab 验证）
- web 层五天连过（D1-D5），web 侧验证体系已完备：boot probe + reader probe + 交互方法论 + 视觉真值

## D4 · 2026-10-16（块A/B/C 全部完成）—— 里程碑达成：lab 里读完中文 EPUB

### 块B 完成（foliate 渲染攻坚，7 轮收敛，未触三振）
- **《紅樓夢》1.15MB/120 回全链验收**：导入（二进制安全）→ 开书 → **CJK 双栏正文完整渲染**（好了歌全文、章节标题、繁体字形）→ **完整分页 1600 页** → 边缘点击翻页 → **进度真实持久化**（[16,1600]→[29]→[41,1600]）→ **目录侧栏**（第一回/第二回条目）→ **深路由重启恢复**（progress 保留，阅读器路由恢复）
- 视觉验证方法论确立：IAB 的 innerText/domSnapshot 对该 React 树返回空（插桩假象），**截图 + 视觉模型分析为渲染真值**；cua 坐标点击是可靠交互通道

### 块B 修出的 bug（全部落地）
1. mock 解码器二进制安全：epub 字节流按 UTF-8 解码撞非法码点 → 严格 UTF-8 + TextEncoder 往返校验，失败走 {__b64} 通道
2. **localsend 重启风暴**：start 答 null → 管理器重启环 ×107；按 LocalSendStatus 契约答 running 态拆环
3. **亮度契约纠错（设备端真 bug）**：get/set_screen_brightness 字段应为 `{brightness}` 非 `{value}`（bridge.ts:96/101）——设备端已修 + mock 补默认（reader 亮度钩子 destructure null 崩溃由此引发）
4. mini-SQL 支持 `--` 行注释（statistics 迁移携带；引号感知剥离）
5. mock fetch 处理 asset 协议前缀（/asset/<encoded>）+ census 载荷截断（1MB 写入的多 MB 字符串撑死页面）

### 块C 完成（语料库 + 回归）
- **testcorpus/**：公版 EPUB ×5——中文 3（紅樓夢/西遊記/三國演義，古腾堡繁体原本，中段 CJK 实证）+ 英文 2（傲慢与偏见/科学怪人）；zip 全验
- lab www/corpus/ 同步（页面内 fetch→base64 种子，绕开 IAB 代理消息上限）；回归 PASS；构建门绿灯

### 给 D5 的输入
- 主题/字号/排版设置验证（阅读器设置面板 UI 可达）；标注/笔记/书内搜索（搜索库链 D3 已通）
- 事件系统 `__deliverEvent`/Channel 端到端可开始接原生源（设备端 D7）
- 设备端待办：RawFileServer 处理 `/asset/<encoded>` 前缀（封面路径，D5/D12）
- IAB 插桩假象清单：innerText/snapshot 空、重分页时 screenshot 面忙、evaluate-click 不可靠——以截图+坐标交互为准

## D4 · 2026-10-15（块A 完成）

### 块A 完成（导入链 lab 全通 + 设备端三件套）
- **移动端文件选择器机制逆向**（本轮最大发现）：Android 路径不走 plugin:dialog，而是 `plugin:native-bridge|show_file_picker` 火后不管 + **Channel 机制回传**——`register_listener {event:'file-picker-result', handler:'__CHANNEL__:<transformCallback id>'}`（Channel 序列化为字符串 `__CHANNEL__:N`），原生经 `window.__deliverEvent(cbId, {index, message:{uris}})` 投递。mock 实现通道表 + show_file_picker 异步投递；shim 加 `__shimEmitEvent`（名称式事件推送口，D5 原生事件系统地基）
- **真实导入链 100% 打通**（lab）：导入书籍→从本地文件导入 → show_file_picker → file-picker-result{uris} → 白名单 → 真实 MD5 哈希 → **plugin:fs|copy_file**（补实现，options 用 toPathBaseDir 非 baseDir）→ Books/<hash>/<书名>.epub + config.json → foliate 元数据解析（真实书名入库）→ library.json 写入 → **卡片渲染 → 点开成书**（"Cover / 1/1 / 第 1 页"）——CRUD-C 闭环
- **设备端三件套落地**（D3 反推输入，构建门 35s 绿灯）：① rangefile.localhost 查询区间协议（/?path=&start=&end= 含端 → X-Total-Size + 切片；filesDir/cacheDir 沙箱守卫）② 深路由 .html 兄弟解析 ③ **books 根修正为 filesDir**（前端自管布局 filesDir/Readest/Books，lab 实证；D2 老假设 filesDir/Books 是错的，readest.ohos.internal 改服务整个 filesDir）
- 设备端 fs 新命令 copy_file（pathWithBase 支持 fromPathBaseDir/toPathBaseDir）；Index.ets 分发 rangefile.localhost；回归 PASS

### 给块B（foliate 渲染攻坚 = web 层最大技术日）
- 准备中文公版 EPUB 语料（2-3 本），CJK 字体/目录/翻页 lab 逐项验证；导入+开书链已通，直接加语料与渲染细节
- register_listener 族 mock 已有通道实现（不再 null），D5 全部原生事件复用同一 Channel 通道

## D3 · 2026-10-15（块A 完成；块B/C 存档见下）

### 块A 完成（turso 7 命令双端实现）
- **契约调研五源合一**：guest-js/index.ts（invoke 命令/返回形状/参数风格 $N）、migrate.ts（PRAGMA user_version 走 select、batch 原子、语句分号预拆）、migrations/index.ts（DDL 面：VIEW/数字积积表/AUTOINCREMENT/UPSERT）、webDatabaseService.ts（web 版即 wasm connect）、relationalStore SDK（executeSql 拒绝 BEGIN/COMMIT → 必须用 beginTransaction；ColumnType 无 FLOAT 是 REAL；ResultSet 空值检查是 isColumnNull）
- **设备端**：新建 `services/NativeDatabase.ets`（relationalStore 直通）：sqlite: URI → databaseDir/rdb/<customDir>/<name> 惩罚性扁平映射（同名 search.db 不同目录不碰撞）；$N/?N → 位置 ? 占位符转换（引号感知）；execute 用 `SELECT changes(), last_insert_rowid()` 补齐 {rowsAffected,lastInsertId}（非 DML 报 0 避免脏 rowid）；batch = beginTransaction/commit/rollBack；select → 行对象数组（getColumnTypeSync 分派 TEXT/INTEGER/REAL/BLOB）。NativeBridge 接线 7 case，构建门绿灯（57s，初版 3 个编译错一轮修完）
- **关键事实修正**：书库/进度本体存 settings.json（fs 层，D2 已通）；turso 只承载辅助 schema（每书搜索索引/OPDS/KOReader 统计/同步映射/reedy）——D3 风险结构比预想轻
- **lab 端**：真 turso WASM 引擎方案被实验否决——wasi-threads 构建 hard-require SharedArrayBuffer 隔离，IAB 视图永远 isolated:false（COOP 头无效），headless --virtual-time-budget 不等 Dedicated Worker 真实时间（两个探针实证）。改为 **mini-SQL 引擎**（~600 行，语句面按 readest 实际 SQL 证据收敛：CREATE/INSERT[OR IGNORE|REPLACE|UPSERT excluded.x]/SELECT[WHERE|ORDER|LIMIT|OFFSET|COALESCE|LIKE ESCAPE|count(*)]/UPDATE/DELETE/DROP TABLE/PRAGMA），localStorage 持久化（labdb_<name>，reload==restart 语义对齐设备文件库）
- **probe_turso.html 探针全绿**（走真 shim invoke 链）：CJK/emoji 往返、行对象形状、__migrations 迁移表、batch 原子+失败回滚、PRAGMA user_version 读写、COALESCE+LIKE+ESCAPE 命中"第一章"、UPSERT、ORDER BY DESC+LIMIT——5 轮修复收敛（未触三振）
- 回归 v1 PASS（boot 不回退）

### 块A 探针抓出的 5 个真 bug（均已修，防复发）
1. `?` 计数必须**整语句共享**（SET 与 WHERE 各自重建计数器 → 双 ? 都绑 params[0]）
2. UPDATE 需按**文本顺序**先解析 SET 再 WHERE（否则 ? 编号颠倒）
3. 普通 INTEGER PRIMARY KEY 的 rowid=现表 max+1（DELETE 后可复用）；AUTOINCREMENT 才持久高水位
4. LIMIT n 是取前 n（slice(offset, offset+limit)），不是跳过
5. tokenizer 标识符不能含 `.`（excluded.name 需拆 token）

### 风险/给块B
- 块B（实验室实证≤8轮）：真实前端触发 turso 的入口=打开书→librarySearchIndex 建 `<hash>/search.db`；目标"书库增删改查+进度全通"主体其实在 fs 层，turso 侧看 search.db 写入+查询
- 设备端遗留验证点（D11-12）：relationalStore 对 `PRAGMA user_version=N`/`PRAGMA wal_checkpoint` 的接受度、changes() 跨 invoke 串扰、customDir 子目录自动创建
- mini-SQL 已覆盖语句面均有源码证据；未见用例（JOIN/子查询/GROUP BY）显式抛错而非静默错答

## D3 · 2026-10-15（块A/B/C 全部完成）—— 里程碑达成

### 块B（实验室实证，6 轮收敛，未触三振）
- **turso 迁移链被真实前端完整触发**：种子 search.db 标记 → 书库全文搜索（?search=text&q=）→ census 记录 load→PRAGMA user_version→__migrations 建表→batch DDL（search_meta/sections/nodes）→meta 查询→wal_checkpoint→close 全链，mini-SQL 引擎零报错，labdb_* 持久化落盘
- **开书全链意外提前打通**（原 D4 里程碑）：真 EPUB（fixture repro-3583）经 mock 二进制通道（{__b64}）→ **rangefile.localhost 查询区间协议**（X-Total-Size 头）→ foliate 完整渲染（章节/分页/进度条/朗读按钮），书籍行被真实流程富化（metadata/metaHash/primaryLanguage/readingStatus/nav.json+config.json 落盘）
- **进度全通**：键盘翻页 → 阅读器真实写入 progress [1,1] + readingStatus=finished → 关书 → 重启 → 卡片显示"已读"徽章 + 开书显示"跳转到上次阅读位置"
- **CRUD**：R=卡片+详情弹窗（真实解析元数据）✓；U=阅读器进度/开书元数据富化/状态更新（真实 updateBook→saveLibraryBooks 链）✓；D=删除三选项→墓碑 deletedAt+fileSyncDeletionRequestedAt+UI 消失 ✓（本地文件清理与云端删除的离线路径留 D5/D8 复核）；C=导入流程按计划属 D4
- **杀进程双分支**：保留存储=重启后书卡/进度/状态完整恢复；清 labfs_/labdb_=全新安装（空库+settings.json 由前端重建）

### 块B 修出的基建/语义（防复发）
1. lab_server.py 无 SPA fallback → 深路由刷新落到目录列表；修为 **.html 同名兄弟解析**（Next 静态导出扁平布局：/library→library.html，RSC→library.txt），资源保留 404（HTML 毒死解析器是坑）
2. 22 个路由壳只 index.html 注了 shim → 深路由静默零启动零报错（连错误收集器都没加载）；全壳注入
3. mock FS 纯字符串存储毁二进制 → 加 {__b64} 二进制通道（读路径直解字节数组）
4. mock fetch 拦截两个内部主机：readest.ohos.internal（静态）+ **rangefile.localhost（查询区间协议，Android 真实路径）**——设备端 ArkWeb 必须同样路由这两个主机（D4/D12 项）
5. 种子教训：书库正主是 `<filesDir>/Readest/Books/library.json`（不是 settings.books）

### 块C（消化+回归）
- 设备端缺口修复：**NativeDatabase.load 落 0 字节标记文件**（前端 databaseExists=fs.exists 门控，relationalStore 放 rdb 目录会永远 false）——构建门绿灯 35s
- 回归 v1 双跑 PASS（regression.sh + lab_check.sh）
- 遗留给 D4：设备端 rangefile.localhost + readest.ohos.internal 双主机路由（RawFileServer）、RawFileServer 深路由 .html 兄弟解析、真机开书；遗留 D5/D8：删除书籍的本地文件清理离线路径、编辑标题弹窗的 UI 自动化（数据层已证）

## D2 · 2026-10-15（块A/B/C 全部完成）

### 完成
- 块A：**fs 插件五件套 + path join + 枚举版 resolve_directory + is_sync_keychain_available + set_webview_info** 全部实现进 NativeBridge.ets，编译一次过
- 契约修正（源码实证，均为原实现潜在真机 bug）：`get_executable_dir`/`resolve_directory` 返回**纯字符串**；`read_text_file` 返回**字节数组**（字符串应答在 CJK 下损坏）；`is_sync_keychain_available` 返回 `{available:true}`
- 块B：mock 与设备语义对齐；修掉 mock 解码器幻影 \0 尾字节；CJK+emoji+ASCII 字节往返全 OK；回归 PASS
- 块C：**null 应答语义归零**——终版审计启动期 TypeError 从 6+ 降到 1（仅剩更新检查 http fetch，前端已优雅捕获，D8 项）；三处新形状修正（`has_ambient_light_sensor`→`{available}`、`get_sync_passphrase` 新增、widgets get→`{instances:[]}`）；发现并修复 mock 的 **plugin 前缀缺失坑**（裸名键静默答 null）；CENSUS.md 三态归档更新；回归 v1 PASS（3 连绿）
- **D2 里程碑达成：设备端命令覆盖 census 全集**（实现或明确降级）

### 停靠
- 无（三轮修复全部收敛：round1 测试方法误用、round2 mock 字节过滤、round3 前缀缺失）

### 踩坑记录（已写入 CENSUS.md 防复发）
1. mock 的 native-bridge 键必须带 `plugin:native-bridge|` 前缀
2. fs 读命令必须答字节数组（CJK 安全）
3. 返回形状以前端 bridge.ts 接口逐条核对

### 风险/次日输入（给 D3）
- D3：turso 7 命令（load/execute/select/batch/sync/get_config/close）→ relationalStore SQL 直通；懒加载触发点=首次书库访问；sync 降级空操作
- D8 前唯一已知错误型 null：plugin:http|fetch（更新检查），不阻塞
- 设备端 fsExtractBytes 数值键升序迭代依赖 JS 整数键排序规范（JSON.parse 产物适用）

## D1 · 2026-10-15

### 完成
- 块A：实验室工具化（lab_up.sh + lab_check.sh 无头Edge判定 + lab_server.py no-store 服务）；mock 桥 localStorage 文件系统（fs 五件套 + path join/resolve_directory，BaseDirectory 枚举实测对齐，UTF-8 字节解码，缺文件 reject 语义）
- 块B：**双轮实证通过**——清空冷启动 settings.json 写入 12787B；刷新（=重启）后读回 0 次失败、UI 正常渲染；lab_check.sh PASS
- 深挖并修复 **Tauri v2 fs 写协议**（本轮最大发现）：write_text_file 的内容=invoke 请求体（字节数组），path/options=invoke options.headers（path URL 编码）。已同步修入：tauri_shim.js（转发 headersJson）→ BridgeProxy（4参）→ NativeBridge.ets（headers 解析合并）。hap 重建绿灯。
- 修复实验室缓存坑：python http.server 无缓存头导致 shim 改后浏览器用旧版 → 换 no-store 自定义服务 + 版本参数击穿
- 前夜已完成（计入 D1 存量）：注入全局三件套修复（__TAURI_OS_PLUGIN_INTERNALS__ 等）、Worker 预防线、hap 重建

### 停靠
- 无（本轮修复循环共 4 轮，全部收敛，未触发三振/停靠）

### 块C 产出（完成）
- **docs/CENSUS.md**：启动期 169 条 invoke 全分类——27 条去重命令按 fs/path/native-bridge/网络/本地五类归档，逐条标注设备端状态（✅9 条已实现 / 🟡18 条待实现并标目标日 / ↘️降级候选）；发现启动门控 `is_sync_keychain_available` 设备端必须答 true（实测答 null = 白屏）
- **scripts/regression.sh v1**：启动→库渲染→语言正确，首跑 **PASS**，历史日志入 .shots/regression.log

### 块D 深潜产出（turso → D3 输入）
- 启动期零 turso 调用（懒加载）；调用链 environment.ts→NativeAppService→NativeDatabaseService→tauri-plugin-turso(submodule)
- 7 条命令面（submodule guest-js 实证）：load/execute/select/batch/sync/get_config/close；打开参数 `sqlite:<AppData>/….db`
- D3 方案：SQL 直通 relationalStore；sync 可降级空操作

### 风险/次日输入（给 D2 块A）
- D2 实现清单（设备端 NativeBridge）：plugin:fs|exists/mkdir/read_text_file/write_text_file/remove（真实 fileIo 实现，注意 headers 协议已在 invoke 解析好 args.path/options）、plugin:path|join、get_executable_dir、set_webview_info
- resolve_directory 收到的是**数字枚举**（13=AppConfig/14=AppData/15=AppLocalData/16=AppCache/19=Executable，@tauri-apps/api path.d.ts），现有按字符串映射的实现需改
- write_text_file 内容在设备端以字节数组 JSON（{0:b,1:b...}）到达，ArkTS 侧需按 UTF-8 还原
- 虚拟主机响应（RawFileServer）建议加 Cache-Control 头，避免 ArkWeb 端重蹈 lab 缓存坑
