import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { nativeBridge } from '../services/NativeBridge';
import { RawFileServer } from '../services/RawFileServer';

const VIRTUAL_HOST: string = 'http://readest.local/index.html';
const BOOKS_HOST_PREFIX: string = 'http://readest.ohos.internal';

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
    Column() {
      if (this.frontendReady) {
        Web({ src: VIRTUAL_HOST, controller: this.controller })
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

  private setupBridge(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    nativeBridge.setController(this.controller, context);
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
