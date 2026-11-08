# COMMANDS.md — 桥接命令三态清单（D7 块C 产出，2026-10-21；D8 块C 增补）

> 权威命令契约表。设备实现源：`entry/src/main/ets/services/NativeBridge.ets`（dispatch switch，101+ case）+ `NativeTts.ets`（Core Speech Kit）。
> 前端契约源：readest `utils/bridge.ts`、`services/tts/NativeTTSClient.ts`、各 hook/service。
> 状态图例：**✅ 已实现**（编译门过，形状对照源码核验）｜**🔬 形状已定，D13 真机核销**（依赖真机 Kit 行为）｜**↘️ 降级**（语义正确的功能降级，返回形状符合契约）｜**🟡 GAP**（未实现，标注目标日）。
> 自测：`pages/SelfTest.ets`（62 用例一键触发；**D9 模拟器实跑 60/62 非 THROW + 2 SKIP（picker 交互类）零 THROW**）。直达入口：`aa start -b com.yueyi.app -a EntryAbility --ps selftest 1`。

## D7 关键契约发现（双端已修，真机免坑）

1. **Tauri v2 Channel 消息序**：`__deliverEvent(id, {index, message})` 只投递 `index === nextIndex` 的消息，其余永久挂起 pending。**每次推送必须按通道单调递增 index**。D7 lab 实证：固定 index=0 时朗读第一句的 `end` 事件被吞，播放卡死在一句。设备端 `emitChannel` 已改 per-Channel 单调计数 + 多监听者广播（`channels: Map<string, number[]>`）。
2. **事件通道是广播语义**：同一 (plugin,event) 多次 register_listener 时全部生效（原生 Kotlin 广播行为），remove_listener 按 channelId 精确移除。
3. **TTS 引擎选择**：readest 默认引擎优先级 Edge（在线 websocket）> native。**`plugin:websocket` 未实现时 Edge 引擎初始化成功但合成挂起**（UI 停"朗读任务加载中"）。lab 以 `localStorage.ttsPreferredVoices.preferredClient='native-tts'` 验证原生链路；设备端 D8 实现 websocket 或接受降级到 native。
4. **null 应答语义**：`localsend_start` 答 null 会引发管理器重启风暴（D4 lab ×107）——必须答 LocalSendStatus 形状。

## D8 关键契约发现（双端已修）

5. **plugin:http `fetch_read_body` 哨兵语义（勘误 D8块A 记录）**：正确契约 = 每次调用返回 `chunk 字节 + 尾部 0` 表示"数据继续"；流结束的下一次调用返回**裸 `[1]`**。dist-js `readChunk` 对 `lastByte===1` 只 close 不 enqueue——**与哨兵 1 同批返回的数据会被整块丢弃**（错误实现 `bytes.concat([1])` 导致 `res.text()` 恒为空）。源码：tauri-plugin-http commands.rs（`chunk.push(0)` / 空流 `vec![1]`）。双端已按此修正。
6. **`download_file`（Rust transfer_file.rs）**：`{url, filePath, headers:Record, body?, singleThreaded?, skipSslVerification?, onProgress:Channel}` → 响应头 `Record<string,string>`；进度经 onProgress Channel 推 `{progress, total, transferSpeed}`（serde camelCase）。OPDS 下载唯一入口（tauriDownload）。设备端等价实现：单请求缓冲 + fsWriteBytes + deliverDirect 一次进度事件。
7. **X-Proxy-Headers 传输格式（lab）**：多请求头时必须 JSON 数组 `[[k,v],...]`——'\n' 拼接值是非法 fetch header value（触发 "Invalid value"）；lab_server 兼容两种格式。
8. **UI 语言真实来源**：`settings.globalViewSettings.uiLanguage`（Providers.applyUILanguage，空则 navigator.language）+ localStorage `i18nextLng`（i18next 检测缓存）。settings.language 不是生效开关。

---

## 1. plugin:native-bridge（45 case ✅/🔬/↘️）

### 系统 / 窗口（22 条裸命令，无 plugin 前缀）
| 命令 | 返回契约 | 状态 |
|---|---|---|
| get_system_color_scheme | `{colorScheme:'dark'\|'light'}` | ✅ D7 形状修正（原 {scheme}） |
| get_status_bar_height | `{height:number}` | ✅ 🔬避让区实测 |
| get_safe_area_insets | `{top,bottom,left,right}` | ✅ 🔬 |
| get_webview_version | string | ✅ |
| get_executable_dir | string（纯字符串，非对象） | ✅ D2 形状修正 |
| get_environment_variable | string\|null | ✅ |
| get_storefront_region_code | string\|null | ✅ 🔬 |
| is_eink_refresh_supported | boolean | ✅（答 false 语义） |
| is_updater_disabled | boolean | ✅ |
| use_background_audio | void | ✅ 🔬后台播放声明 |
| get_media_proxy_base | string\|null | ✅ |
| has_ambient_light_sensor | `{available:boolean}` | ✅ D7 改答 true（AMBIENT_LIGHT 传感器实现就位）🔬 |
| get_sys_fonts_list | `{fonts:Record<string,string>}` | ✅ D7 形状修正（原 string[]） |
| get_screen_brightness | `{brightness:0..1}` | ✅ D4 契约纠错（原 {value}）🔬 |
| set_screen_brightness | 入参 `{brightness,persist?}` | ✅ 🔬 |
| set_screen_wake_lock | void | ✅ 🔬常亮 |
| lock_screen_orientation | void | ✅ 🔬 |
| set_system_ui_visibility | void | ✅ 🔬沉浸式 |
| set_webview_info | void | ✅ 空实现 |
| get_secure_item / set_secure_item / clear_secure_item | `{value:string\|null}` / void | ✅ Asset Kit 🔬 |
| is_sync_keychain_available | `{available:true}` | ✅ |

### 平台能力（plugin:native-bridge|*）
| 命令 | 返回契约 | 状态 |
|---|---|---|
| checkPermissions | `{manageStorage:'granted'}` | ✅ 🔬 |
| request_manage_storage_permission | 同上 | ✅ 🔬真机弹窗 |
| query_pen_capabilities | `{isBoox:false,rawDrawing:false}` | ↘️ 非文石设备语义 |
| icloud_container_status / icloud_ensure_downloaded | `{available:false}` / `{status:'notFound'}` | ↘️ 无 iCloud |
| iap_is_available | `{available:false}` | ↘️ 无 IAP（华为 IAP 后续增强） |
| iap_initialize / fetch_products / purchase / restore | null | ↘️ |
| get_external_sdcard_path | `{path:null}` | ✅ 🔬 |
| get_bookshelf/reading_widget_instances | `{instances:[]}` | ↘️ 服务卡片空（后续增强） |
| set_bookshelf/reading_widget_catalog, update_bookshelf/reading_widget | void | ↘️ |
| auth_with_custom_tab / auth_with_safari | `{success:false}` | ↘️ 登录走系统浏览器方案（D8 核销） |
| install_package | `{success:false}` | ↘️ |
| capture/cover/uncover_webview_region, refresh_eink_screen | `{success:false}` / EinkResult | ↘️ |
| start/stop_raw_drawing | `{success:false}` | ↘️ |
| intercept_keys, set_selection_suppressed | null | ↘️ |
| show_lookup_popover / get_lookup_dictionary / clear_lookup_dictionary | null | ↘️ 词典查词（Web 层词典已可用） |
| read_share_clip_html | null | ↘️ |

### 已实现真功能（D2-D7 逐步落地）
| 命令 | 实现 | 状态 |
|---|---|---|
| show_file_picker | DocumentViewPicker maxNumber:50 → `file-picker-result` 通道 `{uris}` | ✅ 🔬 |
| select_directory | DocumentSelectMode.FOLDER → `{cancelled,uri}` | ✅ 🔬 |
| save_image_to_gallery | MediaAssetChangeRequest.createImageAssetRequest + applyChanges | ✅ 🔬相册权限 |
| copy_uri_to_path | fileIo 沙箱拷贝 → `{success,error}` | ✅ 🔬 |
| set/clear_sync_passphrase, get_sync_passphrase | Asset Kit（key `sync-passphrase`） | ✅ 🔬 |
| start/stop_ambient_light_updates | sensor AMBIENT_LIGHT → `ambient-light` 通道 `{lux}` | ✅ 🔬 |
| set_multicast_lock | void | ↘️（localsend 降级配套） |
| register_listener / remove_listener | Channel id 表 + 广播 + 按 id 移除 | ✅ D7 重写 🔬 |

## 2. plugin:native-tts（18 case，Core Speech Kit）
| 命令 | 返回契约 | 状态 |
|---|---|---|
| init | `{success:boolean}` | ✅ createEngine 🔬 |
| check | `{success}` | ✅ 🔬 |
| speak | `{utteranceId}`，入参 `{payload:{text,preload}}`；事件经 `tts_events` 通道 `{utteranceId,code:'start'\|'end'\|'error',message,mark}` | ✅ 🔬（OHOS 引擎无句级 boundary，前端已验证容忍） |
| stop / pause / resume | void | ✅ 🔬 |
| set_rate / set_pitch / set_voice | void（voice 对象含 id） | ✅ 🔬 |
| get_all_voices | `{voices:[{id,name,lang}]}`（listVoices） | ✅ 🔬 |
| playout_position | `{position:0}` | ↘️ 直读引擎无媒体时钟 |
| playout_enqueue / playout_control | null | ↘️ |
| set_media_session_active / update_media_session_state / update_media_session_metadata | void | ↘️ 系统播控中心后续增强（D13 观察锁屏行为） |
| update_media_library / update_carplay_state | null | ↘️ |

**lab 已端到端验证（D7 块B）**：preferredClient=native-tts 时连续 30 秒 7+ 段落朗读推进、自动翻页（48→51 页）、高亮覆盖层绘制、"本章剩余"时间线倒计时、暂停/恢复正常、干净停机（完整 teardown 序列）。

## 3. plugin:fs（8 case ✅）
read_text_file（**字节数组**）/ write_text_file（headers 协议：字节体+URL-encoded path）/ write_file / read_file / exists（boolean）/ mkdir（recursive）/ remove（unlink/rmdir）/ copy_file（fromPathBaseDir/toPathBaseDir 枚举）— fileIo 沙箱实现，D2 落地。🔬 D12 真机全链路。

## 4. plugin:path（2 case ✅）
join（拼接+归一化→string）/ resolve_directory（数字枚举 13/14/15→filesDir、16→cacheDir、17→filesDir/logs → **纯字符串**）。

## 5. plugin:turso（7 case ✅，relationalStore 直通）
load / execute / select / batch（原子回滚）/ sync（本地库 no-op）/ close / get_config（`{encrypted:false}`）。建库迁移、书库 CRUD、进度恢复 lab 全通（D3-D5）；statistics.db 统计链 D7 修复后全通。🔬 D12 真机落盘。

## 6. localsend（4 case ↘️ D7 补设备端）
start → LocalSendStatus{running:true,…空闲置}（防重启风暴）/ is_alive → true / stop / set_discoverable → void。完整局域网传书（mDNS+HTTP server）为已知降级，见 KNOWN-ISSUES。

## 7. plugin:clipboard-manager（1 case ✅ D7 补）
write_text → pasteboard（JS 侧另有 navigator.clipboard 回退）。🔬 D13 复制引文到外部 App。

## 8. shim 本地应答（不过桥，tauri_shim.js）
plugin:os|*（platform/family/version/arch/type/locale/hostname，伪装 android/mobile/14/aarch64）｜plugin:event|listen/unlisten/emit（本地 pub/sub）｜plugin:window|version 等版本查询。✅ lab+设备同源。

## 8b. 网络命令族（D8 落地 ✅）
- **plugin:websocket**：connect（onMessage Channel 直通道 + headers + await-open 门控）/ send（Text/Binary{number[]}/Close）✅。🔬 D13 Edge TTS 真网（lab 端点不可达，mock 已按域名快速失败——TTSController 引擎探测 15s 超时不再空烧）。
- **plugin:http**：fetch（RID 协议 eager 发起）/ fetch_send / fetch_read_body（**chunk+[0] 续流；裸 [1] 结束**，见契约 5）/ fetch_cancel(_body) ✅。lab OPDS 真网 200 实证；D8 哨兵修正后 res.text() 全量可达。**D10 验证轮复验 PASS**（probe_http：200/8630B/13 头/两段式哨兵）。
- **download_file**（裸命令，transfer_file.rs）：设备 @ohos.net.http 缓冲下载 + fsWriteBytes + deliverDirect 进度 + 响应头 Record ✅；lab 经 /__proxy + labfs 二进制。**OPDS 下载入库 lab 端到端 PASS**（D8 块B）。
- **plugin:deep-link|get_current**（D10 census 审计发现的遗漏，已补）：→ `string[]`（冷启动 URL；空数组=无深链，前端 `urls ?? []` 释放 launch gate；与 shared-intent 双通道并存，前端 markLaunchUrl 去重 #6104）。设备端返回 handleWant 首次记录的启动 uri；lab 返回 []。事件面（deep-link://new-url）不需要：移动端 readest 事件走 shared-intent 通道（useAppUrlIngress 注释自证）。

## 9. 🟡 GAP（未实现 → 目标日）
| 族 | 命令 | 影响 | 目标 |
|---|---|---|---|
| plugin:dialog | open/ask/message | 移动端伪装下不触发（selectFileTauri 走 native-bridge picker）；null 自动取消可接受 | 观察项 |
| plugin:process / shell 等 | — | census 未出现 | 无需 |

## 10. lab 已知 mock 缺口（不影响设备，KNOWN-ISSUES 详录）
- mini-SQL 不支持：表别名 / JOIN / NOT EXISTS / GROUP BY / 顶层 SELECT 列表中的子查询（TTS cache 状态查询、median-duration 查询降级，均已 catch 非致命）
- D7 已补齐：多行 VALUES upsert、ON CONFLICT DO NOTHING、max()/min() 标量函数、算术、标量子查询、SUM/COUNT(DISTINCT)/AVG/MAX 聚合、excluded 语义修正（裸列名=旧行，excluded.X=新行）

---
统计：✅/🔬 实现或形状已定 100+（D8 websocket/http/download_file 族并入）｜ ↘️ 降级（形状正确）22 ｜ 🟡 GAP 0（dialog 为观察项）。合计 107+3 + shim 本地族。
