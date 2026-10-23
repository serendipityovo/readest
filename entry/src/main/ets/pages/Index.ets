import { webview } from '@kit.ArkWeb';
import { common, Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { nativeBridge } from '../services/NativeBridge';
import { RawFileServer } from '../services/RawFileServer';

const VIRTUAL_HOST: string = 'http://readest.local/index.html';
const BOOKS_HOST_PREFIX: string = 'http://readest.ohos.internal';
// 上架审核：隐私政策地址（占位——提审前替换为真实可访问 URL）
const PRIVACY_URL: string = 'https://readest.com/privacy';
// 上架审核：webview 调试通道开关（发布构建打包脚本翻成 false）
const DEBUG_WEB_CHANNEL: boolean = true;

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  fileServer: RawFileServer | null = null;
  @State darkMode: boolean = false;
  @State frontendReady: boolean = false;
  @State extractLabel: string = '正在准备阅读器资源…';
  @State privacyNeeded: boolean = false;

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
    // 上架审核硬项②：首次启动隐私弹窗（国内市场标准要求；同意标记落盘）
    try {
      this.privacyNeeded = !fs.accessSync(`${context.filesDir}/privacy.accepted`);
    } catch (e) {
      this.privacyNeeded = true;
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

  private acceptPrivacy(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const f: fs.File = fs.openSync(`${context.filesDir}/privacy.accepted`,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.closeSync(f.fd);
    } catch (e) {
      // 标记写失败也放行（避免卡死首启），下次再弹
    }
    this.privacyNeeded = false;
  }

  private declinePrivacy(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.terminateSelf();
  }

  private openPrivacy(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const want: Want = { action: 'ohos.want.action.viewData', uri: PRIVACY_URL };
    context.startAbility(want).catch((): void => { /* 无浏览器时忽略 */ });
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

    // 上架审核②：首启隐私弹窗（半透明遮罩 + 政策入口 + 同意/退出）
    if (this.privacyNeeded) {
      Column() {
        Column() {
          Text('隐私政策提示')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 12 })
          Text('本应用为本地电子书阅读器：书籍内容全部来自您本地的文件导入，'
          + '我们不上传您的书籍与阅读记录。应用将按需使用：本地文件读写（导入书籍）、'
          + '剪贴板（复制引文）、网络（您主动配置的在线书城/语音合成）。'
          + '查看完整隐私政策请点击下方链接。')
            .fontSize(14)
            .fontColor('#555555')
            .lineHeight(22)
            .margin({ bottom: 16 })
          Text('《隐私政策》')
            .fontSize(14)
            .fontColor('#007DFF')
            .margin({ bottom: 20 })
            .onClick(() => this.openPrivacy())
          Button('同意并继续')
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor('#007DFF')
            .margin({ bottom: 10 })
            .onClick(() => this.acceptPrivacy())
          Button('不同意并退出')
            .width('100%')
            .height(44)
            .fontSize(16)
            .backgroundColor('#EEEEEE')
            .fontColor('#666666')
            .onClick(() => this.declinePrivacy())
        }
        .width('72%')
        .padding(24)
        .borderRadius(16)
        .backgroundColor('#FFFFFF')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.55)')
      .justifyContent(FlexAlign.Center)
    }
    }
    .width('100%')
    .height('100%')
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
