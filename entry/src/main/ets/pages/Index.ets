import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { nativeBridge } from '../services/NativeBridge';
import { RawFileServer } from '../services/RawFileServer';

const VIRTUAL_HOST: string = 'http://readest.local/index.html';
const BOOKS_HOST_PREFIX: string = 'http://readest.ohos.internal';
// 隐私弹窗：采用 AGC「隐私声明托管」——系统标准化弹窗首启展示，自建弹窗
// 须移除（官方文档：重复弹窗会被上架审核驳回）。政策口径 docs/PRIVACY-POLICY.md
// 上架审核：webview 调试通道开关（发布构建打包脚本翻成 false）
const DEBUG_WEB_CHANNEL: boolean = false;

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  fileServer: RawFileServer | null = null;
  @State darkMode: boolean = false;
  @State frontendReady: boolean = false;
  @State extractLabel: string = '正在准备阅读器资源…';

  aboutToAppear(): void {
    webview.WebviewController.initializeWebEngine();
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 上架审核硬项①：webview 远程调试仅开发期开启。API23 无运行时
    // debuggable 字段，用显式常量门控——发布打包脚本会把它翻成 false
    // （见 docs/PUBLISH.md 发布命令）
    if (DEBUG_WEB_CHANNEL) {
      try {
        webview.WebviewController.setWebDebuggingAccess(true);
      } catch (e) {
        console.error(`[ReadestOhos] setWebDebuggingAccess failed: ${JSON.stringify(e)}`);
      }
    }
    // 单窗口移植默认值：全新安装时种子 openBookInNewWindow=false——桌面
    // 上游默认 true 会走"新窗口开书"路径（WebviewWindow 创建），本移植
    // 无多窗口能力，将静默无反应。已存在的 settings.json 不动（尊重用户
    // 设置）。存在性判断用 statSync（accessSync 本机不可靠，见上）
    try {
      fs.statSync(`${context.filesDir}/settings.json`);
    } catch (e) {
      try {
        const seedF: fs.File = fs.openSync(`${context.filesDir}/settings.json`,
          fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        fs.writeSync(seedF.fd, '{"openBookInNewWindow":false}');
        fs.closeSync(seedF.fd);
        hilog.info(0x0107, 'readestD9', 'settings seeded: openBookInNewWindow=false');
      } catch (e2) {
        hilog.warn(0x0107, 'readestD9', 'settings seed failed: %{public}s',
          JSON.stringify(e2).slice(0, 120));
      }
    }
    this.fileServer = new RawFileServer(context);
    nativeBridge.setController(this.controller, context);
    this.fileServer.extractIfNeeded((done: number, total: number): void => {
      this.extractLabel = `正在准备阅读器资源… ${done}/${total}`;
    })
      .then(() => {
        this.frontendReady = true;
      })
      .catch((err: Error) => {
        console.error(`[ReadestOhos] extract failed: ${err.message}`);
        this.extractLabel = '资源准备异常，仍尝试启动…';
        this.frontendReady = true; // still try: placeholder/404 will show
      });
  }

  build() {
    Stack() {
      Column() {
        if (this.frontendReady) {
        // D12 缓存根治：URL 带 buildstamp 查询参数，每次前端包更新后
        // URL 变化强制绕过 ArkWeb HTTP 缓存（曾供旧 index.html——无内联
        // shim——造成 app service init 失败与幽灵第二文档）
        Web({ src: `${VIRTUAL_HOST}?v=${this.fileServer?.buildStamp() ?? '0'}`, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .onlineImageAccess(true)
          .width('100%')
          .height('100%')
          .onControllerAttached(() => {
            this.setupBridge();
          })
          .onPageEnd(() => {
            // KI-5 诊断：文档加载完成后探测 shim 全局形状（console 经
            // onConsole → hilog，模拟器/真机通用的观察通道）；
            // unhandledrejection 打印堆栈定位 metadata/os_type 错误现场
            try {
              this.controller.runJavaScript(
                "window.addEventListener('unhandledrejection', function(e){" +
                "var r=e&&e.reason;" +
                "console.log('[KI5-REJ]', r&&(r.stack||r.message||String(r)).slice(0,300));});" +
                "window.addEventListener('error', function(e){" +
                "console.log('[KI5-ERR]', e&&e.message, '@', e&&e.filename, ':', e&&e.lineno);});" +
                "var I=window.__TAURI_INTERNALS__;" +
                "console.log('[KI5]', JSON.stringify({" +
                "main:window.top===window," +
                "internals:!!I, metadata:!!(I&&I.metadata)," +
                "invoke:!!(I&&I.invoke), os:!!window.__TAURI_OS_PLUGIN_INTERNALS__," +
                "bridge:!!window.__ohosBridge, ua:navigator.userAgent.slice(0,40)}));");
            } catch (e) {
              console.error(`[ReadestOhos] ki5 probe failed: ${JSON.stringify(e)}`);
            }
          })
          .onInterceptRequest((event) => {
            if (event && event.request && this.fileServer) {
              const url: string = event.request.getRequestUrl();
              if (url.startsWith('http://readest.local') || url.startsWith(BOOKS_HOST_PREFIX)
                || url.startsWith('http://rangefile.localhost')) {
                return this.fileServer.handle(event.request);
              }
            }
            return null;
          })
          .onConsole((event) => {
            // forward page console to hilog: the main observation channel for
            // bridge debugging until on-device devtools are wired up
            if (event) {
              const msg: ConsoleMessage = event.message;
              console.log(`[web:${msg.getSourceId()}:${msg.getLineNumber()}] ${msg.getMessage()}`);
            }
            return false;
          })
          .onErrorReceive((event) => {
            if (event && event.error) {
              console.error(`[ReadestOhos] web error: ${event.error.getErrorInfo()}`);
            }
          })
      } else {
        Column() {
          LoadingProgress().width(48).height(48)
          Text(this.extractLabel)
            .fontSize(14)
            .fontColor('#888888')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.darkMode ? '#000000' : '#ffffff')
    }
    .width('100%')
    .height('100%')
  }

  private setupBridge(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    nativeBridge.setController(this.controller, context);
    // 前端 set_window_title → PC 窗口标题栏（品牌名已由桥内替换为"阅易"）
    nativeBridge.setWindowTitleHandler((title: string): void => {
      window.getLastWindow(context)
        .then((win: window.Window): Promise<void> => win.setWindowTitle(title))
        .then((): void => {
          hilog.info(0x0107, 'readestD9', 'setWindowTitle ok: %{public}s', title.slice(0, 40));
        })
        .catch((err: Error): void => {
          hilog.error(0x0107, 'readestD9', 'setWindowTitle fail: %{public}s',
            JSON.stringify(err).slice(0, 120));
        });
    });
    try {
      // must run before the first load so window.__ohosBridge exists on the page
      this.controller.registerJavaScriptProxy(bridgeProxy, '__ohosBridge', ['invoke', 'notify']);
    } catch (e) {
      console.error(`[ReadestOhos] registerJavaScriptProxy failed: ${JSON.stringify(e)}`);
    }
  }
}

// Proxy object exposed to the page as window.__ohosBridge
class BridgeProxy {
  invoke(cmd: string, reqId: number, payloadJson: string, headersJson: string): void {
    nativeBridge.invoke(cmd, reqId, payloadJson, headersJson);
  }

  notify(cmd: string, payloadJson: string): void {
    nativeBridge.notify(cmd, payloadJson);
  }
}

const bridgeProxy: BridgeProxy = new BridgeProxy();
