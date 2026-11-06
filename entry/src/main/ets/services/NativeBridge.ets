import { window } from '@kit.ArkUI';
import { common, Want } from '@kit.AbilityKit';
import { asset } from '@kit.AssetStoreKit';
import { webview } from '@kit.ArkWeb';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nativeDatabase } from './NativeDatabase';
import { nativeTts } from './NativeTts';
import { picker } from '@kit.CoreFileKit';
import { sensor } from '@kit.SensorServiceKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { webSocket, http } from '@kit.NetworkKit';

interface BrightnessResult { brightness: number }
interface StatusBarResult { height: number }
interface SafeAreaResult { top: number; bottom: number; left: number; right: number }
interface SecureItemResult { value: string | null }
interface ColorSchemeResult { colorScheme: string }
interface KeychainAvailableResult { available: boolean }
interface WidgetInstancesResult { instances: string[] }
interface AmbientSensorResult { available: boolean }
interface SyncPassphraseResult { passphrase: string | null; error: string | null }
interface TursoConfigResult { encrypted: boolean }
// plugin:http RID protocol response shape (plugin-http dist-js fetch_send)
interface PluginHttpResponse {
  status: number;
  statusText: string;
  url: string;
  headers: string[][];
  rid: number;
}
// plugin:websocket onMessage Channel payload shapes (plugin-websocket dist-js)
interface WsCloseData { code: number; reason: string }
interface WsTextMessage { type: string; data: string }
interface WsBinaryMessage { type: string; data: number[] }
interface WsCloseMessage { type: string; data: WsCloseData }
// fs file-handle 组（D12）：read_text_file_lines 的服务端行迭代器
interface LinesIter {
  lines: string[];
  idx: number;
}
interface FsDirent {
  name: string;
  isFile: boolean;
  isDirectory: boolean;
  isSymlink: boolean;
}
interface LinesNextResult {
  value: string | null;
  done: boolean;
}
interface WatchResult {
  rid: number;
}
interface FsStatInfo {
  isFile: boolean;
  isDirectory: boolean;
  isSymlink: boolean;
  size: number;
  mtimeMs: number;
  atimeMs: number;
  birthtimeMs: number;
  readonly: boolean;
}
interface FsHandleRec {
  file: fs.File;
  path: string;
  pos: number;
}
// download_file onProgress Channel payload (transfer_file.rs ProgressPayload,
// serde camelCase)
interface DownloadProgressPayload {
  progress: number;
  total: number;
  transferSpeed: number;
}
interface LocalSendStatus {
  running: boolean;
  alias: string;
  port: number;
  fingerprint: string;
  deviceModel: string;
  localIps: string[];
  multicastError: string | null;
}
interface CopyUriResult { success: boolean; error: string | null }
// shared-intent 事件负载（useAppUrlIngress 消费契约：{urls, action}
// ——D5 lab 实证投递此形状可驱动书籍导入）
interface SharedIntentPayload {
  urls: string[];
  action: string;
}
interface PermissionsResult { manageStorage: string }
interface SdCardResult { path: string | null }
interface SelectDirResult { cancelled?: boolean; uri?: string }
interface SaveGalleryResult { success: boolean; uri?: string; error?: string }
interface AmbientUpdatesResult { success: boolean }
interface EinkResult { success: boolean }
interface ICloudStatusResult { available: boolean }
interface PenCapsResult { isBoox: boolean; rawDrawing: boolean }
interface SyncPassphraseSetResult { success: boolean }
interface TtsInitResult { success: boolean }
interface TtsSpeakResult { utteranceId: string }
interface TtsVoicesResult { voices: Array<Record<string, Object>> }
interface FontsListResult { fonts: Record<string, string> }
interface SuccessResult { success: boolean }
interface PositionResult { position: number }
interface TtsEventPayload { utteranceId: string; code: string; message: string; mark: string | null }
interface FilePickerEvent { uris: string[] }
interface WindowEntry { label: string }
interface AmbientEvent { lux: number }
interface StatusResult { status: string }

/**
 * Dispatches readest native-bridge / tauri-plugin commands to HarmonyOS APIs.
 * Every command resolves (never rejects) when a feature is unavailable on this
 * platform: the frontend treats null/empty as "unsupported" and hides the UI,
 * which matches how readest already handles e-ink / IAP / iCloud on Android.
 */
export class NativeBridge {
  private controller: webview.WebviewController | null = null;
  private context: common.UIAbilityContext | null = null;
  // 窗口标题回调：Index 注入（window.getLastWindow().setWindowTitle）。
  // set_window_title 命令经此把改名后的标题写到 PC 窗口标题栏
  private windowTitleHandler: ((title: string) => void) | null = null;

  setWindowTitleHandler(handler: (title: string) => void): void {
    this.windowTitleHandler = handler;
  }
  private mainWindow: window.Window | null = null;
  private cachedBrightness: number = 0.5;
  private channels: Map<string, number[]> = new Map(); // 'plugin|event' -> Channel callback ids (broadcast)
  private channelSeq: Map<number, number> = new Map(); // per-Channel monotonic message index
  // D9 文件关联：冷启动 want 到达时前端尚未 register_listener，暂存负载，
  // 待 shared-intent 注册到达的瞬间补投（热启动则直接投递）
  private pendingIntent: SharedIntentPayload | null = null;
  private lastIntentKey: string = '';
  private lastIntentAt: number = 0;
  // KI-5 诊断：reqId -> cmd（resolve 打点用）
  private reqCmds: Map<number, string> = new Map();
  // plugin:deep-link|get_current：冷启动 URL 整个会话重复返回（dist-js 契约
  // "keeps returning the launch URL"）；与 shared-intent 补投并存——前端
  // markLaunchUrl 对两条路径做去重（readest #6104 语义）
  private deepLinkLaunchUrls: string[] = [];
  // websocket plugin: per-connect sockets and their onMessage Channel ids
  private wsSockets: Map<number, webSocket.WebSocket> = new Map();
  private wsChannels: Map<number, number> = new Map();
  private wsNextId: number = 1;
  // http plugin (RID protocol): pending request → settled response
  private httpPending: Map<number, Promise<PluginHttpResponse>> = new Map();
  private httpBodies: Map<number, number[]> = new Map();
  private httpNextRid: number = 1;
  private ambientOn: boolean = false;

  /** SelfTest 页入口：无 webview 控制器，仅注入上下文（事件推送静默失败）。 */
  setContextForTest(context: common.UIAbilityContext): void {
    this.context = context;
    nativeDatabase.setContext(context);
    nativeTts.setEventListener((utteranceId: string, code: string, message: string): void => {
      const payload: TtsEventPayload = {
        utteranceId: utteranceId, code: code, message: message, mark: null
      };
      this.emitChannel('native-tts', 'tts_events', payload);
    });
  }

  setController(controller: webview.WebviewController, context: common.UIAbilityContext): void {
    this.controller = controller;
    this.context = context;
    nativeDatabase.setContext(context);
    nativeTts.setEventListener((utteranceId: string, code: string, message: string): void => {
      const payload: TtsEventPayload = {
        utteranceId: utteranceId, code: code, message: message, mark: null
      };
      this.emitChannel('native-tts', 'tts_events', payload);
    });
  }

  /**
   * Push a plugin event through the registered Channel(s) (TTS/intent/ambient).
   * Tauri v2's Channel delivers ONLY the message whose index === nextIndex and
   * parks every other index in a pending buffer — so each emit must carry a
   * per-channel monotonically increasing index. Multiple listeners for the same
   * event each get their own copy (native broadcast semantics). Found in D7
   * lab: a fixed index 0 delivered an utterance's 'start' but parked its 'end',
   * wedging read-aloud after one sentence.
   */
  private emitChannel(plugin: string, event: string, message: Object | null): void {
    const key: string = `${plugin}|${event}`;
    const cbIds: number[] | undefined = this.channels.get(key);
    if (cbIds === undefined || cbIds.length === 0 || !this.controller) {
      return;
    }
    for (const cbId of cbIds) {
      const seq: number = this.channelSeq.get(cbId) ?? 0;
      this.channelSeq.set(cbId, seq + 1);
      const payloadJson: string = JSON.stringify({ index: seq, message: message });
      const script: string =
        `window.__deliverEvent && window.__deliverEvent(${cbId}, ${JSON.stringify(payloadJson)});`;
      try {
        this.controller.runJavaScript(script);
      } catch (e) {
        // page torn down mid-push
      }
    }
  }

  /**
   * Deliver to a DIRECT Channel id (passed per-call as an argument, e.g. the
   * websocket plugin's onMessage Channel) rather than a registered listener.
   * Same Tauri v2 ordering contract as emitChannel: monotonic per-Channel index.
   */
  private deliverDirect(channelId: number, message: Object | string): void {
    if (!this.controller) {
      return;
    }
    const seq: number = this.channelSeq.get(channelId) ?? 0;
    this.channelSeq.set(channelId, seq + 1);
    const payloadJson: string = JSON.stringify({ index: seq, message: message });
    const script: string =
      `window.__deliverEvent && window.__deliverEvent(${channelId}, ${JSON.stringify(payloadJson)});`;
    try {
      this.controller.runJavaScript(script);
    } catch (e) {
      // page torn down mid-push
    }
  }

  /**
   * D9 文件关联：系统"打开方式"want（文件管理器/桌面点 epub/pdf 等）。
   * EntryAbility onCreate/onNewWant 都走这里；uri 形如 file://docs/... 或
   * file://media/...。热启动直接向 shared-intent 通道广播；冷启动页面未起
   * 时暂存，待前端 register_listener('shared-intent') 到达即补投。
   * 去重：同 (uri, action) 5 秒窗口内只投一次（onCreate/onNewWant 双发防护）。
   */
  handleWant(want: Want): void {
    const uri: string = String(want.uri ?? '');
    hilog.info(0x0107, 'readestD9', 'handleWant uri=%{public}s action=%{public}s',
      uri.slice(0, 80), String(want.action ?? ''));
    if (uri === '' || !uri.startsWith('file://')) {
      return; // 深链 readest:// 等其他 want 留给 D11+ 处理
    }
    const wantAction: string = String(want.action ?? '');
    const action: string = wantAction === 'ohos.want.action.sendData' ? 'SEND' : 'VIEW';
    const key: string = `${uri}|${action}`;
    const now: number = Date.now();
    if (key === this.lastIntentKey && now - this.lastIntentAt < 5000) {
      return;
    }
    this.lastIntentKey = key;
    this.lastIntentAt = now;
    if (this.deepLinkLaunchUrls.length === 0) {
      this.deepLinkLaunchUrls = [uri];
    }
    const payload: SharedIntentPayload = { urls: [uri], action: action };
    const listeners: number[] | undefined = this.channels.get('native-bridge|shared-intent');
    if (listeners !== undefined && listeners.length > 0) {
      hilog.info(0x0107, 'readestD9', 'shared-intent emit direct (%{public}d listeners)', listeners.length);
      this.emitChannel('native-bridge', 'shared-intent', payload);
    } else {
      hilog.info(0x0107, 'readestD9', 'shared-intent pending (no listener yet)');
      this.pendingIntent = payload;
    }
  }

  private async ensureWindow(): Promise<window.Window | null> {
    if (this.mainWindow) {
      return this.mainWindow;
    }
    if (!this.context) {
      return null;
    }
    try {
      this.mainWindow = await window.getLastWindow(this.context);
      return this.mainWindow;
    } catch (e) {
      return null;
    }
  }

  /** Entry point registered into the web page as window.__ohosBridge.invoke */
  invoke(cmd: string, reqId: number, payloadJson: string, headersJson: string = 'null'): void {
    hilog.info(0x0107, 'readestD9', 'invoke req=%{public}d cmd=%{public}s', reqId, cmd.slice(0, 60));
    this.reqCmds.set(reqId, cmd);
    let args: Record<string, Object> = {};
    try {
      const parsed: Record<string, Object> = JSON.parse(payloadJson);
      args = parsed;
    } catch (e) {
      // keep empty args (fs write body arrives as a byte map, not an object)
    }
    // Tauri v2 fs write protocol: contents are the invoke body while
    // path/options ride in options.headers (path URL-encoded)
    try {
      if (headersJson && headersJson !== 'null') {
        const headers: Record<string, Object> = JSON.parse(headersJson);
        const headerPath: Object | undefined = headers['path'];
        if (headerPath !== undefined && args['path'] === undefined) {
          args['path'] = decodeURIComponent(String(headerPath));
        }
        const headerOptions: Object | undefined = headers['options'];
        if (headerOptions !== undefined && args['options'] === undefined) {
          args['options'] = JSON.parse(String(headerOptions));
        }
      }
    } catch (e) {
      // headers are optional
    }
    this.dispatch(cmd, args)
      .then((result: Object | null) => {
        this.resolve(reqId, true, result === null ? 'null' : JSON.stringify(result));
      })
      .catch((err: Error) => {
        this.resolve(reqId, false, JSON.stringify(String(err.message || err)));
      });
  }

  /** Native-side observation of frontend events (no-op for now, hook for TTS/sync) */
  notify(cmd: string, payloadJson: string): void {
    // reserved: observe plugin:event|emit traffic from the frontend
  }

  private resolve(reqId: number, ok: boolean, json: string): void {
    const cmdTag: string = this.reqCmds.get(reqId) ?? '?';
    this.reqCmds.delete(reqId);
    hilog.info(0x0107, 'readestD9', 'resolve req=%{public}d ok=%{public}s cmd=%{public}s json=%{public}s',
      reqId, String(ok), cmdTag.slice(0, 44), json.slice(0, 40));
    if (!this.controller) {
      hilog.warn(0x0107, 'readestD9', 'resolve dropped (no controller) req=%{public}d ok=%{public}s', reqId, String(ok));
      return;
    }
    const escaped: string = JSON.stringify(json);
    const script: string = `window.__shimResolve && window.__shimResolve(${reqId}, ${ok}, ${escaped});`;
    try {
      this.controller.runJavaScript(script);
    } catch (e) {
      // page may not be ready yet; drop silently
      hilog.warn(0x0107, 'readestD9', 'resolve runJavaScript threw req=%{public}d', reqId);
    }
  }

  /**
   * D11+/D13 真机核销自测入口（pages/SelfTest.ets）：直接派发一条命令，
   * 返回 JSON 结果或错误文案。与 webview 桥走完全相同的 dispatch 路径。
   */
  async testInvoke(cmd: string, argsJson: string): Promise<string> {
    try {
      let args: Record<string, Object> = {} as Record<string, Object>;
      if (argsJson !== '') {
        const parsed: Record<string, Object> =
          JSON.parse(argsJson) as Record<string, Object>;
        args = parsed;
      }
      const result: Object | null = await this.dispatch(cmd, args);
      const json: string = JSON.stringify(result ?? null);
      return json === undefined ? 'null' : json;
    } catch (e) {
      return `THROW: ${(e as Error).message}`;
    }
  }

  /**
   * picker URI（临时授权、沙箱外）→ 沙箱副本路径。fs.open 支持 picker
   * 返回的 URI；拷贝到 filesDir/imports/ 后路径对 assertSandboxPath 合法。
   * 注意：copyFile(fd,fd) 对 URI 打开的源 fd 静默产出 0 字节（真机实测
   * 2026-10-25），必须用 readSync/writeSync 缓冲循环。
   */
  private async importPickedUriToSandbox(uri: string): Promise<string> {
    const clean: string = decodeURIComponent(uri.split('?')[0]);
    const name: string = clean.substring(clean.lastIndexOf('/') + 1) || `picked_${Date.now()}.bin`;
    const dir: string = `${this.context!.filesDir}/imports`;
    try {
      fs.mkdirSync(dir, true);
    } catch (e) {
      // 已存在
    }
    const dst: string = `${dir}/${name}`;
    const src: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const dstF: fs.File = fs.openSync(dst,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let copied: number = 0;
    try {
      const buf: ArrayBuffer = new ArrayBuffer(262144);
      for (;;) {
        const n: number = fs.readSync(src.fd, buf);
        if (n <= 0) {
          break;
        }
        fs.writeSync(dstF.fd, buf.slice(0, n));
        copied += n;
      }
    } finally {
      fs.closeSync(src);
      fs.closeSync(dstF);
    }
    if (copied === 0) {
      fs.unlinkSync(dst);
      throw new Error(`picked uri yielded 0 bytes: ${uri.slice(0, 80)}`);
    }
    hilog.info(0x0107, 'readestD9', 'picked copied %{public}d bytes -> %{public}s', copied, dst);
    return dst;
  }

  private async dispatch(cmd: string, args: Record<string, Object>): Promise<Object | null> {
    hilog.info(0x0107, 'readestD9', 'dispatch cmd=%{public}s len=%{public}d last=%{public}d',
      cmd.slice(0, 60), cmd.length, cmd.length > 0 ? cmd.charCodeAt(cmd.length - 1) : 0);
    // plugin-listener registration is uniform across plugins (Channel id)
    if (cmd.endsWith('|register_listener')) {
      const plugin: string = cmd.split('|')[0].replace('plugin:', '');
      const handler: Object | undefined = args['handler'];
      const m: RegExpMatchArray | null = String(handler ?? '').match(/^__CHANNEL__:(\d+)$/);
      if (m !== null) {
        const key: string = `${plugin}|${String(args['event'] ?? '')}`;
        const cbId: number = parseInt(m[1], 10);
        const existing: number[] = this.channels.get(key) ?? [];
        if (!existing.includes(cbId)) {
          existing.push(cbId);
        }
        this.channels.set(key, existing);
        // 冷启动文件关联补投：前端 shared-intent 监听就位 = useAppUrlIngress
        // 已挂载，此刻投递必然被消费（app-incoming-url dispatch → 导入链）
        if (key === 'native-bridge|shared-intent' && this.pendingIntent !== null) {
          const held: SharedIntentPayload = this.pendingIntent;
          this.pendingIntent = null;
          hilog.info(0x0107, 'readestD9', 'shared-intent replay from pending: %{public}s',
            held.urls[0] !== undefined ? held.urls[0].slice(0, 60) : '');
          this.emitChannel('native-bridge', 'shared-intent', held);
        }
      }
      return null;
    }
    if (cmd.endsWith('|remove_listener')) {
      const plugin: string = cmd.split('|')[0].replace('plugin:', '');
      const key: string = `${plugin}|${String(args['event'] ?? '')}`;
      const rawId: string = String(args['channelId'] ?? args['handler'] ?? '');
      const channelId: number = parseInt(rawId, 10);
      const existing: number[] | undefined = this.channels.get(key);
      if (existing !== undefined && rawId !== '' && !Number.isNaN(channelId)) {
        const kept: number[] = existing.filter((id: number): boolean => id !== channelId);
        if (kept.length > 0) {
          this.channels.set(key, kept);
        } else {
          this.channels.delete(key);
        }
        this.channelSeq.delete(channelId);
      } else {
        this.channels.delete(key);
      }
      return null;
    }
    // KI-5 根因修复：native-bridge 命令双命名风格统一——历史 case 一批裸名
    // （D2-D6）一批带前缀（D7+），带前缀到达的裸名 case 全部失配返回 null，
    // 曾致首启 TypeError 群（has_ambient .available / status_bar .height…）。
    // 统一为裸名匹配（与 lab mock 的透传语义对齐由 mock 侧双写保证）。
    const bareCmd: string = cmd.startsWith('plugin:native-bridge|')
      ? cmd.substring('plugin:native-bridge|'.length) : cmd;
    switch (bareCmd) {
      // ---- plugin:deep-link（冷启动 URL 查询；census 实测开书会话 ×3）----
      case 'plugin:deep-link|get_current': {
        return this.deepLinkLaunchUrls;
      }

      // ---- native-bridge: system / window ----
      case 'get_system_color_scheme': {
        // contract: {colorScheme} (bridge.ts GetSystemColorSchemeResponse)
        const dark: boolean = this.context?.config?.colorMode === 1 || false;
        const result: ColorSchemeResult = { colorScheme: dark ? 'dark' : 'light' };
        return result;
      }
      case 'get_status_bar_height': {
        const win = await this.ensureWindow();
        const area: window.AvoidArea | null = win
          ? win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM) : null;
        const result: StatusBarResult = { height: area ? area.topRect.height : 0 };
        return result;
      }
      case 'get_safe_area_insets': {
        const win = await this.ensureWindow();
        const sys: window.AvoidArea | null = win
          ? win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM) : null;
        const nav: window.AvoidArea | null = win
          ? win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) : null;
        const result: SafeAreaResult = {
          top: sys ? sys.topRect.height : 0,
          bottom: nav ? nav.bottomRect.height : 0,
          left: sys ? sys.leftRect.width : 0,
          right: sys ? sys.rightRect.width : 0
        };
        return result;
      }
      case 'get_screen_brightness': {
        // contract: {brightness} (bridge.ts:96 GetScreenBrightnessResponse)
        const result: BrightnessResult = { brightness: this.cachedBrightness };
        return result;
      }
      case 'set_screen_brightness': {
        const win = await this.ensureWindow();
        // contract: {brightness, persist?} (bridge.ts:101 SetScreenBrightnessRequest)
        const value: number = Math.min(1.0, Math.max(0.0, Number(args['brightness']) || 0.5));
        this.cachedBrightness = value;
        if (win) {
          await win.setWindowBrightness(value);
        }
        return null;
      }
      case 'set_screen_wake_lock': {
        const win = await this.ensureWindow();
        const on = args['value'] === true || args['value'] === 'true';
        if (win) {
          await win.setWindowKeepScreenOn(on);
        }
        return null;
      }
      case 'lock_screen_orientation': {
        const win = await this.ensureWindow();
        const mode = String(args['orientation'] ?? 'all');
        if (win) {
          if (mode === 'portrait') {
            await win.setPreferredOrientation(window.Orientation.PORTRAIT);
          } else if (mode === 'landscape') {
            await win.setPreferredOrientation(window.Orientation.LANDSCAPE);
          } else {
            await win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
          }
        }
        return null;
      }
      case 'set_system_ui_visibility': {
        const win = await this.ensureWindow();
        const visible = args['visible'] === true;
        if (win && !visible) {
          // fullscreen: dim status/navigation bars; readest restores via the same call
          await win.setSpecificSystemBarEnabled('status', false);
          await win.setSpecificSystemBarEnabled('navigationIndicator', false);
        } else if (win && visible) {
          await win.setSpecificSystemBarEnabled('status', true);
          await win.setSpecificSystemBarEnabled('navigationIndicator', true);
        }
        return null;
      }
      case 'get_sys_fonts_list': {
        // contract: {fonts: Record<fontName, fontFamily>} (bridge.ts)
        const fonts: Record<string, string> = {
          'HarmonyOS Sans': 'HarmonyOS Sans',
          'HarmonyOS Sans SC': 'HarmonyOS Sans SC',
          'HarmonyOS Sans TC': 'HarmonyOS Sans TC',
          'HarmonyOS Serif': 'HarmonyOS Serif',
          'MiSans': 'MiSans'
        };
        const result: FontsListResult = { fonts: fonts };
        return result;
      }
      case 'get_storefront_region_code': {
        return '';
      }
      case 'has_ambient_light_sensor': {
        // OHOS phones expose the ILLUMINANCE sensor (start/stop below)
        hilog.info(0x0107, 'readestD9', 'has_ambient_light_sensor called');
        const result: AmbientSensorResult = { available: true };
        return result;
      }
      case 'get_sync_passphrase': {
        // contract: {passphrase?, error?} — Asset Kit backs the keychain
        const value = await this.assetGet('sync-passphrase');
        const result: SyncPassphraseResult = { passphrase: value, error: null };
        return result;
      }
      case 'is_eink_refresh_supported': {
        return false;
      }
      case 'use_background_audio': {
        return true;
      }

      // ---- native-bridge: secure storage (Asset Store Kit) ----
      case 'set_secure_item': {
        await this.assetPut(String(args['key'] ?? ''), String(args['value'] ?? ''));
        return null;
      }
      case 'get_secure_item': {
        const value = await this.assetGet(String(args['key'] ?? ''));
        const result: SecureItemResult = { value: value };
        return result;
      }
      case 'clear_secure_item': {
        await this.assetRemove(String(args['key'] ?? ''));
        return null;
      }

      // ---- main-process commands the frontend calls early ----
      case 'get_environment_variable': {
        return '';
      }
      case 'get_webview_version': {
        return 'ArkWeb-5.x';
      }
      case 'get_executable_dir': {
        // contract: invoke<string> (nativeAppService.ts:643) — plain string
        return this.context ? this.context.filesDir : '';
      }
      case 'set_webview_info': {
        // Android relays webview settings; ArkWeb is configured on the component
        return null;
      }
      case 'is_sync_keychain_available': {
        // boot gate (bridge.ts:493): {available} — Asset Kit backs the keychain
        const result: KeychainAvailableResult = { available: true };
        return result;
      }
      case 'get_bookshelf_widget_instances':
      case 'get_reading_widget_instances': {
        // contract: {instances} is destructured by the frontend — null throws;
        // OHOS service widgets are a post-parity enhancement, answer empty
        const result: WidgetInstancesResult = { instances: [] };
        return result;
      }
      case 'copy_uri_to_path': {
        // SAF/picker flow (nativeAppService openFile): copy a picked uri into
        // the sandbox. OHOS pickers return file:// URIs (no content:// scheme
        // exists); unsupported schemes answer success:false so the caller can
        // surface the error instead of a crash.
        const payload: Object | undefined = args['payload'];
        let uri: string = '';
        let dst: string = '';
        if (payload !== undefined) {
          const p: Record<string, Object> = payload as Record<string, Object>;
          uri = String(p['uri'] ?? '');
          dst = String(p['dst'] ?? '');
        }
        let src: string = uri.startsWith('file://') ? uri.slice('file://'.length) : uri;
        let err: string | null = null;
        // V-04：dst 此前仅 normalizePath 未走沙箱钳制（README 声称全出口
        // 钳制，此命令漏网）——可写向沙箱内任意路径。补钳制（picker 拷贝
        // 目标本就应在沙箱业务目录内）
        if (src.startsWith('/') && !src.includes('..') && dst.length > 0) {
          try {
            const safeDst: string = this.assertSandboxPath(this.normalizePath(dst));
            this.fsEnsureDir(this.parentDir(safeDst));
            fs.copyFileSync(src, safeDst);
          } catch (e) {
            err = `copy failed: ${src} -> ${dst}`;
          }
        } else {
          err = `unsupported uri: ${uri}`;
        }
        const result: CopyUriResult = { success: err === null, error: err };
        return result;
      }
      case 'get_media_proxy_base': {
        return '';
      }
      case 'is_updater_disabled': {
        return true;
      }

      // ---- path plugin ----
      case 'plugin:path|resolve_directory': {
        // contract: plain string (@tauri-apps/api path.js:124); args carry the
        // numeric BaseDirectory enum (13=AppConfig 14=AppData 16=AppCache ...)
        const n: number = Number(args['directory'] ?? -1);
        if (n > 0) {
          return this.baseDirByEnum(n);
        }
        return this.resolveBaseDir(String(args['base'] ?? ''));
      }
      case 'plugin:path|join': {
        const parts: string[] = JSON.parse(JSON.stringify(args['paths'] ?? '[]'));
        return this.normalizePath(parts.join('/'));
      }

      // ---- fs plugin (sandbox fileIo; return contracts verified against
      //      @tauri-apps/plugin-fs dist-js: reads return byte arrays because
      //      the plugin JS does Uint8Array.from + TextDecoder.decode) ----
      case 'plugin:fs|exists': {
        return this.fsExists(this.fsPath(args));
      }
      case 'plugin:fs|mkdir': {
        const p1: string = this.fsPath(args);
        this.fsEnsureDir(p1);
        return null;
      }
      case 'plugin:fs|read_text_file':
      case 'plugin:fs|read_file': {
        const p2: string = this.fsPath(args);
        if (!this.fsExists(p2)) {
          throw new Error(`file not found: ${p2}`); // Tauri rejects on missing files
        }
        return this.fsReadBytes(p2);
      }
      case 'plugin:fs|write_text_file':
      case 'plugin:fs|write_file': {
        const p3: string = this.fsPath(args);
        this.fsEnsureDir(this.parentDir(p3));
        const bytes: Uint8Array = this.fsExtractBytes(args);
        this.fsWriteBytes(p3, bytes);
        return null;
      }
      case 'plugin:fs|remove': {
        const p4: string = this.fsPath(args);
        this.fsRemove(p4);
        return null;
      }
      case 'plugin:fs|copy_file': {
        // importBook copies the picked file into Books/<hash>/; options carry
        // fromPathBaseDir / toPathBaseDir rather than the usual baseDir
        let from: string = String(args['fromPath'] ?? '');
        if (!from.startsWith('/')) {
          from = this.pathWithBase(from, args['options'], 'fromPathBaseDir');
        }
        let to: string = String(args['toPath'] ?? '');
        if (!to.startsWith('/')) {
          to = this.pathWithBase(to, args['options'], 'toPathBaseDir');
        }
        from = this.assertSandboxPath(this.normalizePath(from));
        to = this.assertSandboxPath(this.normalizePath(to));
        this.fsEnsureDir(this.parentDir(to));
        try {
          fs.copyFileSync(from, to);
        } catch (e) {
          throw new Error(`copy failed: ${from} -> ${to}`);
        }
        return null;
      }
      // ---- fs file-handle 组（D12）：前端 bundle 全量调用面里 open/read/
      //      size/seek/fstat 等此前无 case（default null），曾断 file:// 导入链
      //      （importBook→NativeFile→open 返 null）。语义对齐
      //      @tauri-apps/plugin-fs v2 guest-js。 ----
      case 'plugin:fs|open':
      case 'plugin:fs|create': {
        const fhPath: string = this.assertSandboxPath(this.fsPath(args));
        let mode: number = bareCmd.endsWith('create')
          ? fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE
          : fs.OpenMode.READ_ONLY;
        const fhOpts: Object | undefined = args['options'];
        if (fhOpts !== undefined && fhOpts !== null) {
          const o: Record<string, Object> =
            JSON.parse(JSON.stringify(fhOpts)) as Record<string, Object>;
          const wantWrite: boolean = o['write'] === true || o['append'] === true;
          const wantCreate: boolean = o['create'] === true || o['createNew'] === true;
          const wantTrunc: boolean = o['truncate'] === true;
          if (wantWrite || wantCreate || wantTrunc) {
            mode = fs.OpenMode.READ_WRITE
              | (wantCreate ? fs.OpenMode.CREATE : 0)
              | (o['append'] === true ? fs.OpenMode.APPEND : 0)
              | (wantTrunc ? fs.OpenMode.TRUNC : 0);
          }
        }
        if (!this.fsExists(fhPath) && mode === fs.OpenMode.READ_ONLY) {
          throw new Error(`file not found: ${fhPath}`);
        }
        const fhFile: fs.File = fs.openSync(fhPath, mode);
        const fhRid: number = this.fsNextRid++;
        const rec: FsHandleRec = { file: fhFile, path: fhPath, pos: 0 };
        this.fsHandles.set(fhRid, rec);
        return fhRid;
      }
      case 'plugin:fs|read': {
        // readest 私有协议（NativeFile）：顺序读（无 offset 参数），返回
        // number[] = 数据字节 + 尾 8 字节小端 u64（本次读取字节数；0=EOF）
        const rid: number = this.fsRidOf(args);
        const h: FsHandleRec | undefined = this.fsHandles.get(rid);
        if (h === undefined) {
          throw new Error(`bad file handle: ${rid}`);
        }
        const wantLen: number = Number(args['len'] ?? 0);
        const stat: fs.Stat = fs.statSync(h.path);
        const n: number = Math.min(wantLen, stat.size - h.pos);
        const out: number[] = [];
        if (n > 0) {
          const buf: ArrayBuffer = new ArrayBuffer(n);
          const rd: number = fs.readSync(h.file.fd, buf, { offset: h.pos, length: n });
          h.pos += rd;
          const u8: Uint8Array = new Uint8Array(buf.slice(0, rd));
          for (let i: number = 0; i < u8.length; i++) {
            out.push(u8[i]);
          }
          // append u64-LE of bytes-read
          let v: number = rd;
          for (let b: number = 0; b < 8; b++) {
            out.push(v & 0xFF);
            v = Math.floor(v / 256);
          }
        } else {
          for (let b: number = 0; b < 8; b++) {
            out.push(0); // EOF
          }
        }
        return out;
      }
      case 'plugin:fs|write': {
        const wrid: number = this.fsRidOf(args);
        const wh: FsHandleRec | undefined = this.fsHandles.get(wrid);
        if (wh === undefined) {
          throw new Error(`bad file handle: ${wrid}`);
        }
        const wArr: number[] = args['data'] as Object as number[];
        const wBytes: Uint8Array = new Uint8Array(wArr);
        const wBuf: ArrayBuffer = new ArrayBuffer(wBytes.length);
        new Uint8Array(wBuf).set(wBytes);
        const wOff: number | undefined = args['offset'] !== undefined
          ? Number(args['offset']) : undefined;
        const written: number = fs.writeSync(wh.file.fd, wBuf, wOff !== undefined
          ? { offset: wOff, length: wBytes.length }
          : { offset: wh.pos, length: wBytes.length });
        wh.pos += written;
        return null;
      }
      case 'plugin:fs|size': {
        const srid: number = this.fsRidOf(args);
        const sh: FsHandleRec | undefined = this.fsHandles.get(srid);
        if (sh === undefined) {
          throw new Error(`bad file handle: ${srid}`);
        }
        return fs.statSync(sh.path).size;
      }
      case 'plugin:fs|seek': {
        // readest 私有协议：offset/whence 均为数字（0=start 1=current 2=end），
        // 返回新的绝对位置
        const krid: number = this.fsRidOf(args);
        const kh: FsHandleRec | undefined = this.fsHandles.get(krid);
        if (kh === undefined) {
          throw new Error(`bad file handle: ${krid}`);
        }
        const off: number = Number(args['offset'] ?? 0);
        const whence: number = Number(args['whence'] ?? 0);
        const ks: fs.Stat = fs.statSync(kh.path);
        if (whence === 1) {
          kh.pos = kh.pos + off;
        } else if (whence === 2) {
          kh.pos = ks.size + off;
        } else {
          kh.pos = off;
        }
        return kh.pos;
      }
      case 'plugin:fs|close': {
        const crid: number = this.fsRidOf(args);
        const ch: FsHandleRec | undefined = this.fsHandles.get(crid);
        if (ch !== undefined) {
          this.fsHandles.delete(crid);
          fs.closeSync(ch.file.fd);
        }
        return null;
      }
      case 'plugin:fs|stat':
      case 'plugin:fs|lstat': {
        return this.fsStatInfoOf(this.fsPath(args));
      }
      case 'plugin:fs|fstat': {
        const frid: number = this.fsRidOf(args);
        const fh2: FsHandleRec | undefined = this.fsHandles.get(frid);
        if (fh2 === undefined) {
          throw new Error(`bad file handle: ${frid}`);
        }
        return this.fsStatInfoOf(fh2.path);
      }
      case 'plugin:fs|truncate': {
        const tPath: string = this.fsPath(args);
        const tLen: number | undefined = args['len'] !== undefined
          ? Number(args['len']) : 0;
        if (tLen !== undefined && tLen > 0) {
          // read-modify-write: OHOS fileIo has no ftruncate
          const cur: number[] = this.fsReadBytes(tPath);
          this.fsWriteBytes(tPath, new Uint8Array(cur.slice(0, tLen)));
        } else {
          this.fsWriteBytes(tPath, new Uint8Array(0));
        }
        return null;
      }
      case 'plugin:fs|ftruncate': {
        const trid: number = this.fsRidOf(args);
        const th: FsHandleRec | undefined = this.fsHandles.get(trid);
        if (th === undefined) {
          throw new Error(`bad file handle: ${trid}`);
        }
        return null; // unsupported on OHOS fileIo; book import never uses it
      }
      case 'plugin:fs|rename': {
        let rFrom: string = String(args['fromPath'] ?? args['oldPath'] ?? '');
        let rTo: string = String(args['toPath'] ?? args['newPath'] ?? '');
        if (!rFrom.startsWith('/')) {
          rFrom = this.pathWithBase(rFrom, args['options'], 'fromPathBaseDir');
        }
        if (!rTo.startsWith('/')) {
          rTo = this.pathWithBase(rTo, args['options'], 'toPathBaseDir');
        }
        rFrom = this.assertSandboxPath(this.normalizePath(rFrom));
        rTo = this.assertSandboxPath(this.normalizePath(rTo));
        try {
          fs.renameSync(rFrom, rTo);
        } catch (e) {
          throw new Error(`rename failed: ${rFrom} -> ${rTo}`);
        }
        return null;
      }
      case 'plugin:fs|read_dir': {
        const dirPath: string = this.fsPath(args);
        const names: string[] = fs.listFileSync(dirPath);
        const entries: FsDirent[] = [];
        for (let di: number = 0; di < names.length; di++) {
          const n: string = names[di];
          const st: fs.Stat = fs.statSync(`${dirPath}/${n}`);
          const e: FsDirent = {
            name: n,
            isFile: st.isFile(),
            isDirectory: st.isDirectory(),
            isSymlink: false
          };
          entries.push(e);
        }
        return entries;
      }
      case 'plugin:fs|read_text_file_lines': {
        const lp: string = this.fsPath(args);
        const text: string = this.fsReadText(lp);
        const lrid: number = this.fsNextRid++;
        this.fsLineIters.set(lrid, { lines: text.split('\n'), idx: 0 });
        return lrid;
      }
      case 'plugin:fs|read_text_file_lines_next': {
        const nrid: number = this.fsRidOf(args);
        const it: LinesIter | undefined = this.fsLineIters.get(nrid);
        if (it === undefined) {
          throw new Error(`bad lines handle: ${nrid}`);
        }
        if (it.idx >= it.lines.length) {
          this.fsLineIters.delete(nrid);
          const fin: LinesNextResult = { value: null, done: true };
          return fin;
        }
        const line: string = it.lines[it.idx++];
        const nxt: LinesNextResult = { value: line, done: it.idx >= it.lines.length };
        return nxt;
      }
      case 'plugin:fs|watch': {
        const w: WatchResult = { rid: -1 }; // no FS watcher on OHOS bridge
        return w;
      }
      case 'plugin:fs|unwatch': {
        return null;
      }
      case 'plugin:fs|start_accessing_security_scoped_resource': {
        return this.fsPath(args); // macOS-only concept; echo the path as scope
      }
      case 'plugin:fs|stop_accessing_security_scoped_resource': {
        return null;
      }

      // ---- opener / sharekit / 杂项桌面命令（交付审计补齐：原版点击书内
      //      外链开系统浏览器、分享菜单为用户可见功能）----
      case 'plugin:opener|open_url': {
        // 契约：resolve URL 字符串（实际打开的地址）；系统浏览器承载
        const urlArg: Object | undefined = args['url'];
        const urlStr: string = typeof urlArg === 'string'
          ? urlArg as string : String((urlArg as Record<string, Object>)?.['url'] ?? '');
        if (urlStr.startsWith('http://') || urlStr.startsWith('https://')) {
          const want: Want = {
            action: 'ohos.want.action.viewData',
            uri: urlStr
          };
          this.context!.startAbility(want).catch((e: BusinessError): void => {
            hilog.warn(0x0107, 'readestD9', 'open_url startAbility fail: %{public}s', e.message);
          });
        }
        return urlStr;
      }
      case 'plugin:sharekit|share_text': {
        const sText: string = String(args['text'] ?? args['content'] ?? '');
        const data1: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, sText);
        await pasteboard.getSystemPasteboard().setData(data1);
        return null; // 文本分享经系统粘贴板（鸿蒙 PC 无系统分享面板契约）
      }
      case 'plugin:sharekit|share_file': {
        // 文件分享：拷贝到公共 Download 不可行（权限）；回退复制路径文本
        const sfPath: string = this.fsPath(args);
        const data2: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, sfPath);
        await pasteboard.getSystemPasteboard().setData(data2);
        return null;
      }
      case 'plugin:dialog|message': {
        // 形状应答（消息对话框由前端 toast 承载——readest UI 自带提示层）
        return null;
      }
      case 'plugin:dialog|open': {
        // 桌面语义（os_type=windows）前端 await 本命令返回值拿路径
        // （useFileSelector→selectFileTauri→openDialog multiple:true，
        // 返回 string|string[]|null）；Android 的事件版走 show_file_picker。
        // picker URI 仅临时授权且在沙箱外，这里拷入沙箱 imports/ 再返回
        // 沙箱路径，保证后续 fs|open 过 assertSandboxPath
        const dlgP: Record<string, Object> = this.payloadOf(args);
        const multiple: boolean = dlgP['multiple'] !== undefined && Boolean(dlgP['multiple']);
        const suffixes: string[] = [];
        const filters: Object | undefined = dlgP['filters'];
        if (filters instanceof Array) {
          for (const f of filters as Array<Object>) {
            const fRec: Record<string, Object> = f as Record<string, Object>;
            const exts: Object | undefined = fRec['extensions'];
            if (exts instanceof Array) {
              for (const e of exts as Array<Object>) {
                const s: string = String(e).trim().toLowerCase();
                if (s.length > 0 && s !== '*') {
                  suffixes.push(s.startsWith('.') ? s.slice(1) : s);
                }
              }
            }
          }
        }
        try {
          const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context!);
          const uris: Array<string> = await docPicker.select({
            maxNumber: multiple ? 50 : 1,
            fileSuffixFilters: suffixes
          } as picker.DocumentSelectOptions);
          if (uris.length === 0) {
            return null; // 用户取消（Tauri 语义）
          }
          const paths: string[] = [];
          for (const uri of uris) {
            paths.push(await this.importPickedUriToSandbox(uri));
          }
          hilog.info(0x0107, 'readestD9', 'dialog|open picked=%{public}d first=%{public}s',
            paths.length, paths[0]);
          return multiple ? paths : paths[0];
        } catch (e) {
          hilog.warn(0x0107, 'readestD9', 'dialog|open failed: %{public}s',
            JSON.stringify(e).slice(0, 120));
          return null;
        }
      }
      case 'plugin:dialog|save': {
        const svName: string = String(args['defaultPath'] ?? 'export.bin');
        const svPicker: picker.DocumentSaveOptions = { newFileNames: [svName] };
        const sv: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context!);
        const uris: Array<string> = await sv.save(svPicker);
        return uris.length > 0 ? uris[0] : null;
      }
      case 'reveal_item_in_dir': {
        return null; // OHOS 无"在文件夹中显示"系统 API；前端容错隐藏入口
      }
      case 'plugin:window|get_all_windows': {
        // Tauri 语义：WindowEntry[]。本移植单窗口——恒报 main（与 shim
        // metadata.currentWindow.label 一致）。useOpenWithBooks 等对返回值
        // 直接 .map/.sort，null 会 TypeError（真机 release 回归实测）
        const wins: WindowEntry[] = [{ label: 'main' }];
        return wins;
      }
      case 'set_window_title':
      case 'plugin:window|set_title': {
        // ArkUI 窗口标题由应用名固定；前端书名标题条自渲染，此处形状应答。
        // 改名（审核反馈：与上游 Readest 名称/图标相似）：拦截前端传入的
        // 标题串做品牌替换——窗口标题条不再出现 "Readest" 字样
        // Tauri v2 window.setTitle 传参键是 value（@tauri-apps/api window.js:822），
        // 不是 title——首版按 title 读恒空（hilog 实证 set_title raw=）
        const rawTitle: string = String(args['value'] ?? args['title'] ?? '');
        hilog.info(0x0107, 'readestD9', 'set_title raw=%{public}s', rawTitle.slice(0, 40));
        if (rawTitle.length > 0) {
          const reTitle: string = rawTitle.replace(/readest/gi, '阅易');
          try {
            this.windowTitleHandler?.(reTitle);
          } catch (e) {
            // 标题设置失败不影响功能
          }
        }
        return null;
      }

      // ---- turso plugin (relationalStore pass-through; contract:
      //      src-tauri/plugins/tauri-plugin-turso/guest-js/index.ts) ----
      case 'plugin:turso|load': {
        const opts: Object | undefined = args['options'];
        const loadOptions: Record<string, Object> = opts !== undefined
          ? opts as Record<string, Object>
          : { 'path': String(args['path'] ?? '') };
        return nativeDatabase.load(loadOptions);
      }
      case 'plugin:turso|execute': {
        return nativeDatabase.execute(
          String(args['db'] ?? ''),
          String(args['query'] ?? ''),
          this.argArray(args['values'])
        );
      }
      case 'plugin:turso|select': {
        return nativeDatabase.select(
          String(args['db'] ?? ''),
          String(args['query'] ?? ''),
          this.argArray(args['values'])
        );
      }
      case 'plugin:turso|batch': {
        await nativeDatabase.batch(
          String(args['db'] ?? ''),
          JSON.parse(JSON.stringify(args['queries'] ?? '[]'))
        );
        return null;
      }
      case 'plugin:turso|sync': {
        return nativeDatabase.sync(String(args['db'] ?? ''));
      }
      case 'plugin:turso|close': {
        const dbArg: Object | undefined = args['db'];
        return nativeDatabase.close(dbArg !== undefined && dbArg !== null
          ? String(dbArg) : undefined);
      }
      case 'plugin:turso|get_config': {
        const result: TursoConfigResult = { encrypted: false };
        return result;
      }

      // ---- localsend: degraded to a running-but-idle service so the manager's
      // status polling settles (a null answer restart-stormed ×107 in D4 lab).
      // Full LAN transfer (mDNS + HTTP server) is a documented degradation.
      // 2026-10-26 审核反馈#2（附近设备"显示错误"）：未实现的子命令此前落到
      // 默认分支返回 null，前端对 null .map 直接抛错渲染错误页——补齐全部
      // 命令的安全形状（空设备表/未运行/拒收），让 UI 呈现"无设备"空态而非崩溃
      case 'localsend_start': {
        const status: LocalSendStatus = {
          running: true,
          alias: '阅易',
          port: 53317,
          fingerprint: 'ohos:degraded',
          deviceModel: 'HarmonyOS',
          localIps: [],
          multicastError: null
        };
        return status;
      }
      case 'localsend_get_status': {
        const st: LocalSendStatus = {
          running: true,
          alias: '阅易',
          port: 53317,
          fingerprint: 'ohos:degraded',
          deviceModel: 'HarmonyOS',
          localIps: [],
          multicastError: null
        };
        return st;
      }
      case 'localsend_list_devices': {
        const empty: Object[] = [];
        return empty;
      }
      case 'localsend_is_alive': {
        return true;
      }
      case 'localsend_announce':
      case 'localsend_stop':
      case 'localsend_cancel_receive':
      case 'localsend_cancel_send':
      case 'localsend_set_discoverable': {
        return null;
      }
      case 'localsend_respond': {
        return false; // 未实现接收协商：显式拒收（前端据此终止会话而非报错）
      }
      case 'localsend_send_files': {
        return false; // 未实现发送：前端走失败提示分支
      }

      // ---- clipboard (pasteboard; the JS side falls back to navigator.clipboard
      // when this rejects, but the plugin path keeps copy-quote working in
      // backgrounded WebViews) ----
      case 'plugin:clipboard-manager|write_text': {
        const text: string = String(args['text'] ?? args['contents'] ?? '');
        const data: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
        await pasteboard.getSystemPasteboard().setData(data);
        return null;
      }

      // ---- plugin:websocket（@ohos.net.websocket；契约：@tauri-apps/plugin-websocket dist-js）----
      // Edge TTS（readest 默认 TTS 引擎）的合成通道
      case 'plugin:websocket|connect': {
        const url: string = String(args['url'] ?? '');
        const chMatch: RegExpMatchArray | null =
          String(args['onMessage'] ?? '').match(/^__CHANNEL__:(\d+)$/);
        const channelId: number = chMatch !== null ? parseInt(chMatch[1], 10) : -1;
        const ws: webSocket.WebSocket = webSocket.createWebSocket();
        const wsId: number = this.wsNextId++;
        ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
          if (err) {
            this.deliverDirect(channelId, `ws message error: ${err.message}`);
            return;
          }
          if (typeof value === 'string') {
            const textMsg: WsTextMessage = { type: 'Text', data: value };
            this.deliverDirect(channelId, textMsg);
          } else {
            const bytes: number[] = Array.from(new Uint8Array(value));
            const binMsg: WsBinaryMessage = { type: 'Binary', data: bytes };
            this.deliverDirect(channelId, binMsg);
          }
        });
        ws.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
          if (err) {
            this.deliverDirect(channelId, `ws close error: ${err.message}`);
            return;
          }
          const closeData: WsCloseData = { code: value.code, reason: value.reason };
          const closeMsg: WsCloseMessage = { type: 'Close', data: closeData };
          this.deliverDirect(channelId, closeMsg);
          this.wsSockets.delete(wsId);
          this.wsChannels.delete(wsId);
        });
        ws.on('error', (err: BusinessError) => {
          this.deliverDirect(channelId, `ws error: ${err.message}`);
        });
        const headerRec: Record<string, string> = {};
        const config: Record<string, Object> =
          JSON.parse(JSON.stringify(args['config'] ?? '{}')) as Record<string, Object>;
        const pairs: Object[] | undefined = config['headers'] as Object[] | undefined;
        if (pairs !== undefined) {
          for (const pair of pairs) {
            const kv: string[] = JSON.parse(JSON.stringify(pair)) as string[];
            if (kv.length >= 2) {
              headerRec[kv[0]] = kv[1];
            }
          }
        }
        const connOpts: webSocket.WebSocketRequestOptions = { header: headerRec };
        const ok: boolean = await ws.connect(url, connOpts);
        if (!ok) {
          throw new Error(`websocket connect failed: ${url}`);
        }
        this.wsSockets.set(wsId, ws);
        this.wsChannels.set(wsId, channelId);
        return wsId;
      }
      case 'plugin:websocket|send': {
        const wsId: number = parseInt(String(args['id'] ?? '0'), 10);
        const ws: webSocket.WebSocket | undefined = this.wsSockets.get(wsId);
        if (ws === undefined) {
          throw new Error(`websocket not found: ${wsId}`);
        }
        const message: Record<string, Object> =
          JSON.parse(JSON.stringify(args['message'] ?? '{}')) as Record<string, Object>;
        const type: string = String(message['type'] ?? '');
        if (type === 'Text') {
          await ws.send(String(message['data'] ?? ''));
        } else if (type === 'Binary') {
          const nums: number[] = JSON.parse(JSON.stringify(message['data'] ?? '[]')) as number[];
          await ws.send(new Uint8Array(nums).buffer);
        } else if (type === 'Close') {
          await ws.close();
        }
        return null;
      }

      // ---- plugin:http（@ohos.net.http；RID 协议：fetch → fetch_send → fetch_read_body）----
      case 'plugin:http|fetch': {
        const cfg: Record<string, Object> =
          JSON.parse(JSON.stringify(args['clientConfig'] ?? '{}')) as Record<string, Object>;
        const rid: number = this.httpNextRid++;
        const reqUrl: string = String(cfg['url'] ?? '');
        const method: string = String(cfg['method'] ?? 'GET').toUpperCase();
        const req: http.HttpRequest = http.createHttp();
        const headerRec: Record<string, string> = {};
        const pairs: Object[] | undefined = cfg['headers'] as Object[] | undefined;
        if (pairs !== undefined) {
          for (const pair of pairs) {
            const kv: string[] = JSON.parse(JSON.stringify(pair)) as string[];
            if (kv.length >= 2) {
              headerRec[kv[0]] = kv[1];
            }
          }
        }
        const opts: http.HttpRequestOptions = {
          method: method as http.RequestMethod,
          header: headerRec,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 60000
        };
        const dataVal: Object | undefined = cfg['data'];
        if (dataVal !== undefined) {
          if (typeof dataVal === 'string') {
            opts.extraData = dataVal;
          } else {
            const nums: number[] = JSON.parse(JSON.stringify(dataVal)) as number[];
            opts.extraData = new Uint8Array(nums).buffer;
          }
        }
        const work: Promise<PluginHttpResponse> = req.request(reqUrl, opts).then(
          (rsp: http.HttpResponse): PluginHttpResponse => {
            const headerObj: Record<string, Object> =
              (rsp.header ?? {}) as Record<string, Object>;
            const flat: string[][] = [];
            const keys: string[] = Object.keys(headerObj);
            for (const k of keys) {
              const v: Object | undefined = headerObj[k];
              if (v !== undefined && v !== null) {
                flat.push([k, String(v)]);
              }
            }
            const bodyBytes: number[] = rsp.result instanceof ArrayBuffer
              ? Array.from(new Uint8Array(rsp.result as ArrayBuffer))
              : Array.from(new util.TextEncoder().encodeInto(String(rsp.result ?? '')));
            this.httpBodies.set(rid, bodyBytes);
            req.destroy();
            const info: PluginHttpResponse = {
              status: rsp.responseCode,
              statusText: '',
              url: reqUrl,
              headers: flat,
              rid: rid
            };
            return info;
          }
        ).catch((e: BusinessError): PluginHttpResponse => {
          req.destroy();
          throw new Error(`http request failed: ${e.message}`);
        });
        this.httpPending.set(rid, work);
        return rid;
      }
      case 'plugin:http|fetch_send': {
        const rid: number = parseInt(String(args['rid'] ?? '0'), 10);
        const work: Promise<PluginHttpResponse> | undefined = this.httpPending.get(rid);
        if (work === undefined) {
          throw new Error(`http request not found: ${rid}`);
        }
        return await work;
      }
      case 'plugin:http|fetch_read_body': {
        const rid: number = parseInt(String(args['rid'] ?? '0'), 10);
        const body: number[] | undefined = this.httpBodies.get(rid);
        const bytes: number[] = body ?? [];
        // Rust plugin contract (commands.rs): each read returns one chunk with
        // a 0 sentinel appended while data flows; the stream end is a BARE [1]
        // on the next call — dist-js discards data that arrives with the 1
        if (bytes.length > 0) {
          this.httpBodies.set(rid, []);
          return bytes.concat([0]);
        }
        this.httpBodies.delete(rid);
        this.httpPending.delete(rid);
        return [1];
      }
      case 'plugin:http|fetch_cancel':
      case 'plugin:http|fetch_cancel_body': {
        const rid: number = parseInt(String(args['rid'] ?? '0'), 10);
        this.httpPending.delete(rid);
        this.httpBodies.delete(rid);
        return null;
      }

      // ---- download_file（src-tauri transfer_file.rs；OPDS 书籍下载）----
      // Rust contract: GET/POST url with headers, stream body to filePath,
      // report ProgressPayload{progress,total,transferSpeed} on the onProgress
      // Channel, resolve with the response headers as a flat record.
      // Equivalent implementation: one buffered request + one final progress
      // event (books are a few MB; readest's UI tolerates chunk-less updates).
      case 'download_file': {
        const dlUrl: string = String(args['url'] ?? '');
        const dlPath: string = this.assertSandboxPath(this.normalizePath(String(args['filePath'] ?? '')));
        hilog.info(0x0107, 'readestD9', 'download_file url=%{public}s path=%{public}s',
          dlUrl.slice(0, 60), dlPath.slice(0, 70));
        const dlHeaderRec: Record<string, string> = {};
        const dlHeaders: Object | undefined = args['headers'];
        if (dlHeaders !== undefined && dlHeaders !== null) {
          const kvRec: Record<string, Object> =
            JSON.parse(JSON.stringify(dlHeaders)) as Record<string, Object>;
          const dlKeys: string[] = Object.keys(kvRec);
          for (const hk of dlKeys) {
            dlHeaderRec[hk] = String(kvRec[hk] ?? '');
          }
        }
        const chMatch: string[] =
          String(args['onProgress'] ?? '').match(/^__CHANNEL__:(\d+)$/) ?? [];
        const progressCh: number = chMatch.length >= 2 ? parseInt(chMatch[1], 10) : -1;
        const bodyArg: Object | undefined = args['body'];
        const dlOpts: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          header: dlHeaderRec,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 300000
        };
        if (bodyArg !== undefined && bodyArg !== null) {
          dlOpts.method = http.RequestMethod.POST;
          dlOpts.extraData = String(bodyArg);
        }
        const dlReq: http.HttpRequest = http.createHttp();
        // KI-7 看门狗（V-14 改进）：系统 http 栈对不可达 TLS 站点可能永不
        // 回调（readTimeout 不触发）——超时强制失败避免永挂。原先固定 20s
        // 会误杀慢网大书；改为"有进度即续期"：headers/data 事件每次重置
        // 20s 计时，不可达站点（零事件）仍在 20s 内失败
        let dlWd: number = -1;
        let wdReject: (e: Error) => void = (): void => {};
        const armWatchdog = (): void => {
          if (dlWd >= 0) {
            clearTimeout(dlWd);
          }
          dlWd = setTimeout((): void => {
            wdReject(new Error('download watchdog timeout (20s no progress)'));
          }, 20000);
        };
        const dlWatchdog: Promise<never> = new Promise<never>(
          (_resolve, reject): void => {
            wdReject = reject;
            armWatchdog();
          });
        try {
          dlReq.on('headersReceive', (): void => armWatchdog());
          dlReq.on('dataReceive', (): void => armWatchdog());
        } catch (e) {
          // 事件注册失败退化为固定 20s 看门狗（已在计时）
        }
        const dlRsp: http.HttpResponse = await Promise
          .race([dlReq.request(dlUrl, dlOpts), dlWatchdog])
          .catch((e: BusinessError): http.HttpResponse => {
            if (dlWd >= 0) {
              clearTimeout(dlWd);
            }
            dlReq.destroy();
            throw new Error(`download failed: ${e.message}`);
          });
        if (dlWd >= 0) {
          clearTimeout(dlWd);
        }
        dlReq.destroy();
        if (dlRsp.responseCode >= 400) {
          throw new Error(`http error code ${dlRsp.responseCode}`);
        }
        const dlBytes: Uint8Array = dlRsp.result instanceof ArrayBuffer
          ? new Uint8Array(dlRsp.result as ArrayBuffer)
          : new util.TextEncoder().encodeInto(String(dlRsp.result ?? ''));
        hilog.info(0x0107, 'readestD9', 'download_file done code=%{public}d bytes=%{public}d', dlRsp.responseCode, dlBytes.length);
        this.fsEnsureDir(this.parentDir(dlPath));
        this.fsWriteBytes(dlPath, dlBytes);
        if (progressCh >= 0) {
          const progressMsg: DownloadProgressPayload = {
            progress: dlBytes.length,
            total: dlBytes.length,
            transferSpeed: dlBytes.length
          };
          this.deliverDirect(progressCh, progressMsg);
        }
        const dlHeaderObj: Record<string, Object> =
          (dlRsp.header ?? {}) as Record<string, Object>;
        const dlResult: Record<string, string> = {};
        const dlKeys2: string[] = Object.keys(dlHeaderObj);
        for (const hk of dlKeys2) {
          const hv: Object | undefined = dlHeaderObj[hk];
          if (hv !== undefined && hv !== null) {
            dlResult[hk] = String(hv);
          }
        }
        return dlResult;
      }

      // ---- native-tts (Core Speech Kit; contract: NativeTTSClient.ts) ----
      case 'plugin:native-tts|init': {
        const ok: boolean = await nativeTts.init();
        const result: TtsInitResult = { success: ok };
        return result;
      }
      case 'plugin:native-tts|speak': {
        const p: Record<string, Object> = this.payloadOf(args);
        const text: string = String(p['text'] ?? '');
        const preload: boolean = p['preload'] === true;
        const utteranceId: string = await nativeTts.speak(text, preload);
        const result: TtsSpeakResult = { utteranceId: utteranceId };
        return result;
      }
      case 'plugin:native-tts|stop': {
        nativeTts.stop();
        return null;
      }
      case 'plugin:native-tts|pause': {
        nativeTts.pause();
        return null;
      }
      case 'plugin:native-tts|resume': {
        return null; // no engine pause/resume; matches Android reference
      }
      case 'plugin:native-tts|set_rate': {
        nativeTts.setRate(Number(this.payloadOf(args)['rate'] ?? 1));
        return null;
      }
      case 'plugin:native-tts|set_pitch': {
        nativeTts.setPitch(Number(this.payloadOf(args)['pitch'] ?? 1));
        return null;
      }
      case 'plugin:native-tts|set_voice': {
        const p4: Record<string, Object> = this.payloadOf(args);
        const vObj: Object | undefined = p4['voice'];
        let id: string = '';
        if (vObj !== undefined) {
          const voiceRec: Record<string, Object> = JSON.parse(JSON.stringify(vObj)) as Record<string, Object>;
          id = String(voiceRec['id'] ?? '');
        }
        nativeTts.setVoice(id);
        return null;
      }
      case 'plugin:native-tts|get_all_voices': {
        const list = JSON.parse(JSON.stringify(await nativeTts.voices())) as Array<Record<string, Object>>;
        const result: TtsVoicesResult = { voices: list };
        return result;
      }
      case 'plugin:native-tts|check': {
        const result: TtsInitResult = { success: true };
        return result;
      }
      // audiobook streaming player / media-session surfaces: no OHOS engine
      // equivalent in this milestone — void/no-op answers keep callers stable
      case 'plugin:native-tts|playout_enqueue':
      case 'plugin:native-tts|playout_control':
      case 'plugin:native-tts|set_media_session_active':
      case 'plugin:native-tts|update_media_session_metadata':
      case 'plugin:native-tts|update_media_session_state':
      case 'plugin:native-tts|update_media_library':
      case 'plugin:native-tts|update_carplay_state': {
        return null;
      }
      case 'plugin:native-tts|playout_position': {
        const pos: PositionResult = { position: 0 };
        return pos;
      }

      // ---- native-bridge: pickers / storage / sensors ----
      case 'show_file_picker': {
        // fire-and-forget: results arrive as file-picker-result{uris}
        try {
          // 交付审计修复：无参构造（全局上下文）从 web invoke 调用栈弹出
          // 后 select() promise 永挂（真机 picker 关闭但回调不回）；显式传
          // UIAbility context 使回调路由回本能力窗口
          const docPicker: picker.DocumentViewPicker =
            new picker.DocumentViewPicker(this.context!);
          const uris: Array<string> = await docPicker.select({
            maxNumber: 50,
            fileSuffixFilters: []
          } as picker.DocumentSelectOptions);
          hilog.info(0x0107, 'readestD9', 'picker returned %{public}d uris', uris.length);
          const evt: FilePickerEvent = { uris: uris };
          this.emitChannel('native-bridge', 'file-picker-result', evt);
        } catch (e) {
          hilog.warn(0x0107, 'readestD9', 'picker failed: %{public}s', JSON.stringify(e).slice(0, 80));
          // cancelled: emit nothing (matches Android semantics)
        }
        return null;
      }
      case 'select_directory': {
        try {
          // V-06：无参构造（全局上下文）从 web 调用栈 select() 永挂——
          // show_file_picker 同款问题（交付审计已修），此处补齐：显式传
          // UIAbility context 使回调路由回本能力窗口
          const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(this.context!);
          const uris: Array<string> = await docPicker.select({
            maxNumber: 1,
            selectMode: picker.DocumentSelectMode.FOLDER
          } as picker.DocumentSelectOptions);
          if (uris.length > 0) {
            const result: SelectDirResult = { uri: uris[0] };
            return result;
          }
          const cancelled: SelectDirResult = { cancelled: true };
          return cancelled;
        } catch (e) {
          const cancelled: SelectDirResult = { cancelled: true };
          return cancelled;
        }
      }
      case 'save_image_to_gallery': {
        // API12 write path: MediaAssetChangeRequest.createImageAssetRequest
        // takes the sandbox file straight into the user gallery
        const p2: Record<string, Object> = this.payloadOf(args);
        const srcPath: string = String(p2['srcPath'] ?? '');
        try {
          const fileUri: string = 'file://' + srcPath;
          const req: photoAccessHelper.MediaAssetChangeRequest =
            photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(this.context!, fileUri);
          const helper: photoAccessHelper.PhotoAccessHelper =
            photoAccessHelper.getPhotoAccessHelper(this.context!);
          await helper.applyChanges(req);
          const result: SaveGalleryResult = { success: true };
          return result;
        } catch (e) {
          const result: SaveGalleryResult = { success: false, error: String(e) };
          return result;
        }
      }
      case 'set_sync_passphrase': {
        const p3: Record<string, Object> = this.payloadOf(args);
        await this.assetPut('sync-passphrase', String(p3['passphrase'] ?? ''));
        const result: SyncPassphraseSetResult = { success: true };
        return result;
      }
      case 'clear_sync_passphrase': {
        await this.assetRemove('sync-passphrase');
        const result: SyncPassphraseSetResult = { success: true };
        return result;
      }
      case 'start_ambient_light_updates': {
        // lux pushes ride the 'ambient-light' Channel event (themeStore)
        try {
          if (!this.ambientOn) {
            this.ambientOn = true;
            sensor.on(sensor.SensorId.AMBIENT_LIGHT, (data: sensor.LightResponse) => {
              const evt: AmbientEvent = { lux: data.intensity };
              this.emitChannel('native-bridge', 'ambient-light', evt);
            });
          }
          const result: AmbientUpdatesResult = { success: true };
          return result;
        } catch (e) {
          const result: AmbientUpdatesResult = { success: false };
          return result;
        }
      }
      case 'stop_ambient_light_updates': {
        try {
          sensor.off(sensor.SensorId.AMBIENT_LIGHT);
          this.ambientOn = false;
          const result: AmbientUpdatesResult = { success: true };
          return result;
        } catch (e) {
          const result: AmbientUpdatesResult = { success: false };
          return result;
        }
      }
      case 'checkPermissions':
      case 'request_manage_storage_permission': {
        // OHOS apps live in a sandbox: shared-storage access is not a permission
        const result: PermissionsResult = { manageStorage: 'granted' };
        return result;
      }
      case 'get_external_sdcard_path': {
        const result: SdCardResult = { path: null };
        return result;
      }

      // ---- native-bridge: platform-specific, degraded with correct shapes ----
      case 'auth_with_custom_tab':   // Chrome Custom Tabs (Android)
      case 'auth_with_safari': {     // ASWebAuthenticationSession (iOS)
        const r: SuccessResult = { success: false };
        return r;
      }
      case 'iap_is_available': {
        const r: KeychainAvailableResult = { available: false };
        return r;
      }
      case 'iap_initialize':
      case 'iap_fetch_products':
      case 'iap_purchase_product':
      case 'iap_restore_purchases': {
        return null;
      }
      case 'icloud_container_status': {
        const result: ICloudStatusResult = { available: false };
        return result;
      }
      case 'icloud_ensure_downloaded': {
        const st: StatusResult = { status: 'notFound' };
        return st;
      }
      case 'query_pen_capabilities': {
        const result: PenCapsResult = { isBoox: false, rawDrawing: false };
        return result;
      }
      case 'start_raw_drawing':
      case 'stop_raw_drawing':
      case 'refresh_eink_screen': {
        const result: EinkResult = { success: false };
        return result;
      }
      case 'capture_webview_region':
      case 'cover_webview_region':
      case 'uncover_webview_region': {
        const r: SuccessResult = { success: false };
        return r;
      }
      case 'install_package': {
        const r: SuccessResult = { success: false };
        return r;
      }
      // no-ops on OHOS: no multicast lock / key interception / lookup popovers
      case 'set_multicast_lock':
      case 'intercept_keys':
      case 'set_selection_suppressed':
      case 'read_share_clip_html':
      case 'show_lookup_popover':
      case 'get_lookup_dictionary':
      case 'clear_lookup_dictionary':
      case 'set_bookshelf_widget_catalog':
      case 'set_reading_widget_catalog':
      case 'update_bookshelf_widget':
      case 'update_reading_widget': {
        return null;
      }

      default: {
        // Unknown command: resolve null so the frontend can degrade gracefully.
        return null;
      }
    }
  }

  // ---- fs/path helpers ----

  /** Invoke args arrive as generic Object; round-trip to a typed array. */
  private argArray(v: Object | undefined): Object[] {
    if (v === undefined || v === null) {
      return [];
    }
    return JSON.parse(JSON.stringify(v)) as Object[];
  }

  /** Mobile-plugin payloads arrive wrapped as {payload: {...}}. */
  private payloadOf(args: Record<string, Object>): Record<string, Object> {
    const p: Object | undefined = args['payload'];
    if (p !== undefined && p !== null) {
      return JSON.parse(JSON.stringify(p)) as Record<string, Object>;
    }
    return args;
  }

  /** Prefix a relative path with the sandbox dir named by options[key]. */
  private pathWithBase(p: string, opts: Object | undefined, key: string): string {
    if (opts !== undefined) {
      try {
        const o: Record<string, Object> = JSON.parse(JSON.stringify(opts));
        const bd: number = Number(o[key] ?? 0);
        if (bd > 0 && p.charAt(0) !== '/') {
          return `${this.baseDirByEnum(bd)}/${p}`;
        }
      } catch (e) {
        // unreadable options: treat path as-is
      }
    }
    return p;
  }

  /** Resolve an fs-plugin call to an absolute sandbox path. */
  private fsPath(args: Record<string, Object>): string {    let p: string = String(args['path'] ?? '');
    // KI-5 file:// 导入链：shared-intent 送来的 uri 带 file:// 前缀，
    // fileIo 需要纯路径（openFile→NativeFile 分支不剥前缀）
    if (p.startsWith('file://')) {
      p = p.substring('file://'.length);
    }
    const opts: Object | undefined = args['options'];
    if (opts !== undefined) {
      try {
        const o: Record<string, Object> = JSON.parse(JSON.stringify(opts));
        const bd: number = Number(o['baseDir'] ?? 0);
        if (bd > 0 && p.charAt(0) !== '/') {
          p = `${this.baseDirByEnum(bd)}/${p}`;
        }
      } catch (e) {
        // unreadable options: treat path as-is
      }
    }
    return this.assertSandboxPath(this.normalizePath(p));
  }

  /** Tauri BaseDirectory enum (path.d.ts) -> OHOS sandbox dir. */
  private baseDirByEnum(n: number): string {
    if (!this.context) {
      return '';
    }
    if (n === 2 || n === 12 || n === 16) {
      return this.context.cacheDir; // Cache / Temp / AppCache
    }
    if (n === 17) {
      return `${this.context.filesDir}/logs`; // AppLog
    }
    return this.context.filesDir; // AppConfig / AppData / AppLocalData / others
  }

  /**
   * 安全审计加固（2026-10-25）：桥接 fs 命令的中央沙箱钳制——绝对路径
   * 仅允许 filesDir / cacheDir 前缀（全部合法业务路径都在这两根下：
   * settings.json、Readest/Books、inbox、logs、Cache 缩略图等）。同源
   * iframe（恶意书籍内容）此前可借 fs 命令读写沙箱内任意文件；上游
   * Tauri 有 capability scope 等价约束。OHOS fileIo 本身已把进程限制在
   * 应用沙箱，此钳制防御沙箱内越权（如篡改 settings/library）。
   */
  private assertSandboxPath(p: string): string {
    if (!this.context) {
      return p;
    }
    const files: string = this.context.filesDir;
    const cache: string = this.context.cacheDir;
    // 前缀必须含尾部分隔符（V-05）：无分隔符的 startsWith 会放过
    // …/files_evil/x、…/cacheX/y 一类同前缀兄弟目录（白盒 harness T2 实证）
    const under: boolean = (root: string, q: string): boolean =>
      q === root || (root.length > 0 && q.startsWith(`${root}/`));
    const ok: boolean = under(files, p) || under(cache, p);
    if (!ok) {
      throw new Error(`path outside app sandbox: ${p.slice(0, 60)}`);
    }
    return p;
  }

  private normalizePath(p: string): string {
    const abs: boolean = p.charAt(0) === '/';
    const parts: string[] = [];
    const segs: string[] = p.split('/');
    for (let i = 0; i < segs.length; i++) {
      const s: string = segs[i];
      if (s === '' || s === '.') {
        continue;
      }
      if (s === '..') {
        if (parts.length > 0) {
          parts.pop();
        }
        continue;
      }
      parts.push(s);
    }
    return (abs ? '/' : '') + parts.join('/');
  }

  private fsExists(p: string): boolean {
    try {
      return fs.accessSync(p);
    } catch (e) {
      return false;
    }
  }

  // ---- fs file-handle 组（D12）----
  private fsHandles: Map<number, FsHandleRec> = new Map();
  private fsLineIters: Map<number, LinesIter> = new Map();
  private fsNextRid: number = 1;

  private fsRidOf(args: Record<string, Object>): number {
    return Number(args['rid'] ?? -1);
  }

  private fsStatInfoOf(p: string): FsStatInfo {
    if (!this.fsExists(p)) {
      throw new Error(`file not found: ${p}`);
    }
    const st: fs.Stat = fs.statSync(p);
    const info: FsStatInfo = {
      isFile: st.isFile(),
      isDirectory: st.isDirectory(),
      isSymlink: false,
      size: st.size,
      mtimeMs: (st.mtime ?? 0) * 1000,
      atimeMs: (st.atime ?? 0) * 1000,
      birthtimeMs: (st.mtime ?? 0) * 1000,
      readonly: false
    };
    return info;
  }

  private fsReadText(p: string): string {
    const bytes: number[] = this.fsReadBytes(p);
    const arr: Uint8Array = new Uint8Array(bytes);
    return new util.TextDecoder().decodeToString(arr);
  }

  private fsEnsureDir(p: string): void {
    if (!p || this.fsExists(p)) {
      return;
    }
    try {
      fs.mkdirSync(p, true);
    } catch (e) {
      // already created concurrently
    }
  }

  private parentDir(p: string): string {
    const i: number = p.lastIndexOf('/');
    return i > 0 ? p.slice(0, i) : '';
  }

  private fsReadBytes(p: string): number[] {
    const stat: fs.Stat = fs.statSync(p);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    const file: fs.File = fs.openSync(p, fs.OpenMode.READ_ONLY);
    try {
      fs.readSync(file.fd, buf);
    } finally {
      fs.closeSync(file);
    }
    const view: Uint8Array = new Uint8Array(buf);
    const out: number[] = [];
    for (let i = 0; i < view.length; i++) {
      out.push(view[i]);
    }
    return out;
  }

  /**
   * Write payload bytes. Tauri fs write protocol: contents arrive either as a
   * string, a byte-map ({0:..,1:..}), or — when path/options rode in headers —
   * as the byte-map body itself with path/options merged in (skipped here).
   */
  private fsExtractBytes(args: Record<string, Object>): Uint8Array {
    const contents: Object | undefined = args['contents'];
    if (typeof contents === 'string') {
      const encoder = new util.TextEncoder();
      return encoder.encodeInto(contents);
    }
    const src: Record<string, Object> = contents !== undefined
      ? contents as Record<string, Object> : args;
    const vals: number[] = [];
    const keys: string[] = Object.keys(src);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (k.length > 0 && k.charCodeAt(0) >= 48 && k.charCodeAt(0) <= 57) {
        vals.push(Number(src[k]) & 0xFF);
      }
    }
    return new Uint8Array(vals); // JSON object integer keys iterate ascending
  }

  private fsWriteBytes(p: string, bytes: Uint8Array): void {
    const buf: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buf).set(bytes);
    const file: fs.File = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buf);
    } finally {
      fs.closeSync(file);
    }
  }

  private fsRemove(p: string): void {
    try {
      const stat: fs.Stat = fs.statSync(p);
      if (stat.isDirectory()) {
        fs.rmdirSync(p);
      } else {
        fs.unlinkSync(p);
      }
    } catch (e) {
      // missing or already removed
    }
  }

  private resolveBaseDir(base: string): string {
    if (!this.context) {
      return '';
    }
    if (base === 'AppCache' || base === 'Temp' || base === 'Cache') {
      return this.context.cacheDir;
    }
    if (base === 'AppData' || base === 'AppConfig' || base === 'Data' || base === 'Config'
      || base === 'LocalData' || base === 'CurrentExe') {
      return this.context.filesDir;
    }
    if (base === 'Download' || base === 'DownloadDir') {
      return '/storage/Users/currentUser/Downloads';
    }
    if (base === 'Document' || base === 'DocumentDir') {
      return '/storage/Users/currentUser/Documents';
    }
    return this.context.filesDir;
  }

  private async assetPut(key: string, value: string): Promise<void> {
    if (!key) {
      return;
    }
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, stringToArray(key).slice(0, 1024));
    query.set(asset.Tag.SECRET, stringToArray(value));
    try {
      await asset.add(query);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 24000003) { // already exists -> remove then re-add
        await this.assetRemove(key);
        await asset.add(query).catch(() => {
        });
      }
    }
  }

  private async assetGet(key: string): Promise<string | null> {
    if (!key) {
      return null;
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToArray(key).slice(0, 1024));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const res: Array<asset.AssetMap> = await asset.query(query);
      if (res && res.length > 0) {
        const v = res[0].get(asset.Tag.SECRET);
        if (v instanceof Uint8Array) {
          return arrayToString(v);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  private async assetRemove(key: string): Promise<void> {
    if (!key) {
      return;
    }
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, stringToArray(key).slice(0, 1024));
      await asset.remove(query);
    } catch (e) {
      // ignore
    }
  }
}

function stringToArray(s: string): Uint8Array {
  const arr: number[] = [];
  for (let i = 0; i < s.length; i++) {
    arr.push(s.charCodeAt(i));
  }
  return new Uint8Array(arr);
}

function arrayToString(arr: Uint8Array): string {
  let s: string = '';
  for (let i = 0; i < arr.length; i++) {
    s += String.fromCharCode(arr[i]);
  }
  return s;
}

export const nativeBridge: NativeBridge = new NativeBridge();
