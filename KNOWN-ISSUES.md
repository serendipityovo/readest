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

### KI-5 模拟器首启前端早期 TypeError 群 + file:// fetch ERR_FAILED（D11 攻坚域，D9 新档）
- **现象**（模拟器 hilog ARKWEB-CONSOLE，启动 1-2s 窗口）：`Cannot read properties of null (reading 'error'/'height')`、`reading 'invoke'`、`reading 'os_type'`、`reading 'metadata'` ×5+——疑似 shim 就绪时序或某资源加载失败级联；后续 SelfTest 60/62 通过说明桥后来全通
- **file:// fetch ERR_FAILED**：shared-intent 文件导入链的最后一步（importBook 读 file:// uri）——ArkWeb 对 file:// 的 fetch 限制
- **归属**：计划 D11 预定攻坚域（"真实前端首启攻坚：拦截时机/proxy 注册/CSP——预案B 本地 socket 加载备选"）；修复方向：RawFileServer 拦截 file:// 转 fs，或前端导入路径走桥读取
- **观察工具**：`hilog | grep ARKWEB-CONSOLE`（前端 console 全量；模拟器/真机通用）

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
