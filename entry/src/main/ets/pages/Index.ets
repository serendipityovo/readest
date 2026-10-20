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
    const context = getContext(this) as common.UIAbilityContext;
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
    const context = getContext(this) as common.UIAbilityContext;
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
