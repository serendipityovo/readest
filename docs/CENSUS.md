# CENSUS.md — invoke 调用面分类表（D1 产出，D2-D5 持续更新）

## D5 新增实证（2026-10-16）
- **shared-intent 事件契约**（useAppUrlIngress.ts）：`{urls: string[], action?: 'VIEW'|'SEND'}`，经 Channel（register_listener 'shared-intent'）投递 → app-incoming-url 事件 → useOpenWithBooks 导入——**D9 文件关联的真机机制**，lab 已端到端复刻
- **选择菜单面**：拖选后弹 划线/笔记/搜索/词典/翻译/朗读/文字校对 + 高亮/下划线/波浪线 + 五色；标注落盘 `Books/<hash>/config.json.booknotes[]`（id/type/cfi/style/color/text/note/page/时间戳）
- **阅读器设置面**：滑杆 屏幕亮度/阅读进度/字号/页面边距/行间距/跳转位置；开关 滚动/自动滚动/段落/快读/自动主题等；行间距落盘 globalViewSettings.lineHeight
- **回归基建**：boot 检查需独立 profile（书库有书→封面 img 打 readest.ohos.internal → headless DNS 挂死 hydration，纯 lab 现象）；READER-PROBE 已入 regression v2


## D4 块B 新增实证（2026-10-16）
- **localsend 族契约**（service.ts）：`start{alias,deviceModel}`→LocalSendStatus{running,alias,port,fingerprint,deviceModel,localIps,multicastError}｜`is_alive`→boolean｜`stop`/`set_discoverable`→void。**null 应答会引发重启风暴**（×107 实测）
- **亮度契约纠错**：`get_screen_brightness`→`{brightness:0..1}`、`set_screen_brightness` 收 `{brightness,persist?}`（bridge.ts:96/101）——设备端原实现 {value} 已修（潜在真机 bug 提前消灭）
- **asset 协议路径**：封面等资源 URL 形如 `readest.ohos.internal/asset/<url-encoded-abs>`——mock 已剥前缀；**设备端 RawFileServer 需同样处理**（D5/D12 待办）
- 红楼梦开书链实证：rangefile 查询区间读 1.15MB 全书、1600 页分页、TOC 120 回、进度持久化 [page,total] 数组形态


> 数据来源：浏览器实验室冷启动实测（169 条 invoke，去重 27 条桥接命令 + 本地应答命令）+ D2 块C 终版 null 审计。
> 设备状态：✅已实现（NativeBridge.ets）｜🟡待实现（标注目标日）｜↘️明确降级（语义正确，不阻塞）。
> **D2 里程碑达成：启动 census 全集已覆盖（实现或明确降级），启动期 TypeError 归零到 1 条已知 D8 项（更新检查 http fetch，前端已优雅捕获）。**

## 启动期调用面（按类归档，D2 后状态）

### 文件系统（fs 插件）— D2 全部落地 ✅
| 命令 | 次数 | 状态 |
|---|---|---|
| `plugin:fs|read_text_file` | 44 | ✅ 返回**字节数组**（插件 JS 做 TextDecoder），缺文件 reject |
| `plugin:fs|write_text_file` | 28 | ✅ headers 协议（字节体+headers path/options），数值键升序提取 |
| `plugin:fs|exists` | 6 | ✅ 返回 boolean |
| `plugin:fs|mkdir` | 2 | ✅ recursive，返回 void |
| `plugin:fs|remove` | 0* | ✅ 文件 unlink / 目录 rmdir（*启动未见，删书触发） |

### 路径（path 插件）— D2 落地 ✅
| 命令 | 次数 | 状态 |
|---|---|---|
| `plugin:path|join` | 19 | ✅ 拼接+归一化，返回字符串 |
| `plugin:path|resolve_directory` | 17 | ✅ 数字枚举（13/14/15→filesDir，16→cacheDir，17→filesDir/logs），返回**纯字符串** |

### native-bridge 系统类
| 命令 | 次数 | 状态 |
|---|---|---|
| `plugin:native-bridge|is_sync_keychain_available` | 1 | ✅ D2：`{available:true}`（启动门控） |
| `plugin:native-bridge|get_sync_passphrase` | 1 | ✅ D2 新增：`{passphrase:null,error:null}` |
| `get_executable_dir` | 1 | ✅ D2 形状修正：纯字符串 |
| `set_webview_info` | 1 | ✅ D2：空实现（ArkWeb 组件级配置） |
| `plugin:native-bridge|has_ambient_light_sensor` | 1 | ✅ D2 形状修正：`{available:false}` |
| `plugin:native-bridge|get_safe_area_insets` | 3 | ✅ |
| `plugin:native-bridge|get_status_bar_height` | 1 | ✅ `{height}` |
| `plugin:native-bridge|set_system_ui_visibility` | 3 | ✅ |
| `plugin:native-bridge|lock_screen_orientation` | 1 | ✅ |
| `get_webview_version` | 1 | ✅ |
| `plugin:native-bridge|get_bookshelf_widget_instances` | 1 | ✅ D2：`{instances:[]}`（空数组语义；服务卡片列为后续增强） |
| `plugin:native-bridge|get_reading_widget_instances` | 1 | ✅ 同上 |
| `plugin:native-bridge|set_bookshelf_widget_catalog` | 1 | ↘️ void 降级 |
| `plugin:native-bridge|set_reading_widget_catalog` | 1 | ↘️ void 降级 |
| `plugin:native-bridge|register_listener` | 6 | 🟡 D7（原生事件推送源：亮度/方向/深色变化） |
| `plugin:native-bridge|remove_listener` | 2 | 🟡 D7 |
| `plugin:native-bridge|set_multicast_lock` | 1 | ↘️ D7 降级（localsend 发现） |
| `localsend_start` | 1 | ↘️ D7 降级（局域网传书） |

### 网络与入口
| 命令 | 次数 | 状态 |
|---|---|---|
| `plugin:http|fetch` | 1 | 🟡 D8（启动期为更新检查，null 降级 → 前端 warn 后继续，**唯一剩余错误型 null**） |
| `plugin:http|fetch_send` | 1 | 🟡 D8 |
| `plugin:deep-link|get_current` | 4 | 🟡 D9；null = "无启动链接" 语义正确 |

### 本地应答（shim 直接处理）✅
`plugin:event|*`、`plugin:os|*`、插件 version 查询。

## 已实现但未在启动期触发的命令
get/set_screen_brightness、set_screen_wake_lock、get_system_color_scheme、get_sys_fonts_list、secure items×3、is_eink_refresh_supported、get_storefront_region_code、get_environment_variable、get_media_proxy_base、use_background_audio —— 开书/TTS/设置页时复核。

## turso 深潜结论（D3 全天完成：双端实现 + 真实前端实证，2026-10-15）
- **启动期零调用**：懒加载；书库全文搜索（?search=text）经 databaseExists(search.db) 文件探测门控后触发。
- 链路：NativeAppService（nativeAppService.ts:1022，`sqlite:${绝对路径}`）→ NativeDatabaseService → tauri-plugin-turso(guest-js 实证)。
- **7 命令面**：`load{options}`→路径回显字符串｜`execute{db,query,values}`→`{rowsAffected,lastInsertId}`｜`select`→行对象数组｜`batch{db,queries}`→原子｜`sync`→no-op｜`close{db?}`→true｜`get_config`→`{encrypted:false}`。
- **D3 落地并实证**：设备端 NativeDatabase.ets（relationalStore 直通 + $N→? 转换 + beginTransaction + changes()/last_insert_rowid() 补返回 + **0 字节标记文件**保 databaseExists 门控）；lab 端 mini-SQL 引擎（localStorage 持久化）。真实前端触发全迁移链零报错。
- **事实**：书库/进度本体在 `<filesDir>/Readest/Books/library.json`（fs 层）；turso 只承载辅助 schema（library-search/OPDS/statistics/同步映射/reedy）。
- **wasm 引擎不可用实证**：@readest/turso-database-wasm 为 wasi-threads 构建，需 SharedArrayBuffer 隔离——IAB 视图 isolated:false（COOP 无效）、headless 虚拟时钟不等 Worker。mini-SQL 为 lab 替代。
- 设备端 D11-12 验证点：PRAGMA 接受度、changes() 串扰、customDir 自动创建、标记文件与 deleteDatabase 的互动。

## D4 块A 新增实证（2026-10-15）
- **Channel 机制**（Tauri v2 插件监听）：`addPluginListener` → `plugin:<plugin>|register_listener {event, handler:'__CHANNEL__:<id>'}`；原生投递 = `window.__deliverEvent(<id>, '{"index":N,"message":{...}}')`——D5 所有原生事件推送（亮度/方向/深色/intent）复用此通道
- **导入调用面**：`show_file_picker`(火后不管) → `file-picker-result{uris}` → `copy_file{fromPath(绝对), toPath(相对), options{toPathBaseDir}}` → hash 目录落书
- mock 新命令：register_listener/remove_listener（通道表）、show_file_picker（事件回放）、copy_file、plugin:dialog|open/save/ask
- 设备端 RawFileServer：+rangefile.localhost 协议、深路由 .html 兄弟、books 根=filesDir（前端布局 filesDir/Readest/Books）

## D3 新增 D4/D12 设备端输入（lab 实证反推）
1. **rangefile.localhost 查询区间协议**：Android 路径开书走 `http://rangefile.localhost/?path=<abs>&start=&end=`（含端），应答 X-Total-Size 头 + 切片字节——RawFileServer/拦截必须支持（lab 已由 mock fetch 实现并跑通整条开书链）
2. **readest.ohos.internal 静态路由**：convertFileSrc 产物的 fetch 直取
3. **深路由 .html 兄弟解析**：Next 扁平导出 /library→library.html；根壳在深路由渲染空白网格；RawFileServer 需同 lab_server.py 的解析规则（资源 404 保持）
4. mock 基建沉淀：二进制通道 {__b64}、22 路由壳全注入 shim、SPA fallback

## D2 踩坑记录（防复发）
1. mock 的 native-bridge 命令键**必须带 `plugin:native-bridge|` 前缀**——裸名 miss 后静默答 null。
2. fs 读命令必须答**字节数组**；字符串应答在 CJK 下按 256 取模损坏（ASCII 内容侥幸通过）。
3. 返回形状以前端 `bridge.ts` 接口为准逐条核对（本次修正 4 处对象/字符串形状错误）。

## 回归口径
启动→库渲染→语言正确 = lab_check 关键词 `书库` + `导入`（regression.sh v1）。
