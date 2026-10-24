import { common } from '@kit.AbilityKit';
import { nativeBridge } from '../services/NativeBridge';

/**
 * D7 块C 自测页：每命令一键触发，显示 dispatch 真实返回值。
 * 用途：D11 冒烟验桥 + D13 命令核销（对照 docs/COMMANDS.md 三态清单）。
 * 入口：DevEco 预览/真机 router.pushUrl('pages/SelfTest')；不依赖 webview。
 */
interface TestCase {
  group: string;
  cmd: string;
  args: string;
  skip?: string; // 交互类命令弹系统 UI 且阻塞等用户，自动跑会挂死整页
}

interface RowState {
  result: string;
  running: boolean;
}

@Entry
@Component
struct SelfTest {
  @State rows: RowState[] = [];
  @State summary: string = '未运行';
  private cases: TestCase[] = [
    // ---- native-bridge：系统/窗口 ----
    { group: '系统', cmd: 'get_system_color_scheme', args: '' },
    { group: '系统', cmd: 'get_status_bar_height', args: '' },
    { group: '系统', cmd: 'get_safe_area_insets', args: '' },
    { group: '系统', cmd: 'get_webview_version', args: '' },
    { group: '系统', cmd: 'get_executable_dir', args: '' },
    { group: '系统', cmd: 'get_environment_variable', args: '{"name":"HOME"}' },
    { group: '系统', cmd: 'get_storefront_region_code', args: '' },
    { group: '系统', cmd: 'is_eink_refresh_supported', args: '' },
    { group: '系统', cmd: 'is_updater_disabled', args: '' },
    { group: '系统', cmd: 'use_background_audio', args: '' },
    { group: '系统', cmd: 'get_media_proxy_base', args: '' },
    { group: '系统', cmd: 'has_ambient_light_sensor', args: '' },
    { group: '系统', cmd: 'get_sys_fonts_list', args: '' },
    // ---- 亮度/方向/常亮（D13 真机重点）----
    { group: '屏幕', cmd: 'get_screen_brightness', args: '' },
    { group: '屏幕', cmd: 'set_screen_brightness', args: '{"brightness":0.6,"persist":false}' },
    { group: '屏幕', cmd: 'set_screen_wake_lock', args: '{"enabled":true}' },
    { group: '屏幕', cmd: 'lock_screen_orientation', args: '{"orientation":1}' },
    { group: '屏幕', cmd: 'set_system_ui_visibility', args: '{"visible":true}' },
    // ---- 安全存储 ----
    { group: '密钥', cmd: 'is_sync_keychain_available', args: '' },
    { group: '密钥', cmd: 'set_secure_item', args: '{"key":"selftest","value":"ok"}' },
    { group: '密钥', cmd: 'get_secure_item', args: '{"key":"selftest"}' },
    { group: '密钥', cmd: 'clear_secure_item', args: '{"key":"selftest"}' },
    { group: '密钥', cmd: 'get_sync_passphrase', args: '' },
    { group: '密钥', cmd: 'set_sync_passphrase', args: '{"passphrase":"selftest-pass"}' },
    // ---- native-bridge：平台能力 ----
    { group: '平台', cmd: 'plugin:native-bridge|checkPermissions', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|query_pen_capabilities', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|icloud_container_status', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|iap_is_available', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|get_external_sdcard_path', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|get_bookshelf_widget_instances', args: '' },
    { group: '平台', cmd: 'plugin:native-bridge|get_reading_widget_instances', args: '' },
    // ---- 事件通道（Channel 注册/注销 + index 单调性由 D13 真机核销）----
    { group: '通道', cmd: 'plugin:native-tts|register_listener', args: '{"event":"tts_events","handler":"__CHANNEL__:9001"}' },
    { group: '通道', cmd: 'plugin:native-tts|remove_listener', args: '{"event":"tts_events","channelId":9001}' },
    // ---- 文件选择（真机会弹系统 picker）----
    { group: '选择器', cmd: 'plugin:native-bridge|show_file_picker', args: '{"title":"自测选书"}',
      skip: '交互类，弹系统选择器阻塞（D13 真机手验）' },
    { group: '选择器', cmd: 'plugin:native-bridge|select_directory', args: '',
      skip: '交互类，弹系统选择器阻塞（D13 真机手验）' },
    // ---- 传感器 ----
    { group: '传感器', cmd: 'plugin:native-bridge|start_ambient_light_updates', args: '' },
    { group: '传感器', cmd: 'plugin:native-bridge|stop_ambient_light_updates', args: '' },
    // ---- TTS（Core Speech Kit；事件推送需 webview 在场，返回值形状此处可验）----
    { group: 'TTS', cmd: 'plugin:native-tts|init', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|check', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|get_all_voices', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|set_rate', args: '{"payload":{"rate":1.5}}' },
    { group: 'TTS', cmd: 'plugin:native-tts|set_pitch', args: '{"payload":{"pitch":1.2}}' },
    { group: 'TTS', cmd: 'plugin:native-tts|speak', args: '{"payload":{"text":"鸿蒙朗读自测","preload":false}}' },
    { group: 'TTS', cmd: 'plugin:native-tts|pause', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|resume', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|stop', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|playout_position', args: '' },
    { group: 'TTS', cmd: 'plugin:native-tts|set_media_session_active', args: '{"payload":{"active":false}}' },
    // ---- 数据库（scratch 库往返）----
    { group: 'DB', cmd: 'plugin:turso|load', args: '{"options":{"path":"sqlite:/data/storage/el2/base/files/selftest.db"}}' },
    { group: 'DB', cmd: 'plugin:turso|execute', args: '{"db":"sqlite:/data/storage/el2/base/files/selftest.db","query":"CREATE TABLE IF NOT EXISTS t (id INTEGER PRIMARY KEY, v TEXT)"}' },
    { group: 'DB', cmd: 'plugin:turso|execute', args: '{"db":"sqlite:/data/storage/el2/base/files/selftest.db","query":"INSERT INTO t (v) VALUES (?)","values":["hi"]}' },
    { group: 'DB', cmd: 'plugin:turso|select', args: '{"db":"sqlite:/data/storage/el2/base/files/selftest.db","query":"SELECT id, v FROM t"}' },
    // ---- fs / path ----
    { group: 'FS', cmd: 'plugin:path|join', args: '{"paths":["/data","storage","x"]}' },
    { group: 'FS', cmd: 'plugin:path|resolve_directory', args: '{"directory":14}' },
    { group: 'FS', cmd: 'plugin:fs|mkdir', args: '{"path":"selftest","options":{"baseDir":14,"recursive":true}}' },
    { group: 'FS', cmd: 'plugin:fs|write_text_file', args: '{"path":"selftest/x.txt","contents":"ok","options":{"baseDir":14}}' },
    { group: 'FS', cmd: 'plugin:fs|read_text_file', args: '{"path":"selftest/x.txt","options":{"baseDir":14}}' },
    { group: 'FS', cmd: 'plugin:fs|exists', args: '{"path":"selftest/x.txt","options":{"baseDir":14}}' },
    { group: 'FS', cmd: 'plugin:fs|remove', args: '{"path":"selftest/x.txt","options":{"baseDir":14}}' },
    // ---- localsend / clipboard ----
    { group: '其他', cmd: 'localsend_start', args: '' },
    { group: '其他', cmd: 'localsend_is_alive', args: '' },
    { group: '其他', cmd: 'plugin:clipboard-manager|write_text', args: '{"text":"readest 自测"}' },
    // ---- 网络族（D10.5 增：设备侧 @ohos.net.http 真网核销）----
    { group: '网络', cmd: 'plugin:http|fetch', args: '{"clientConfig":{"method":"GET","url":"https://www.gutenberg.org/ebooks.opds/","headers":[["User-Agent","Readest/1.0"]]}}',
      skip: '返回 rid 需 fetch_send 接力，D13 真机手测链路' },
    { group: '网络', cmd: 'download_file', args: '{"url":"https://mirrors.tuna.tsinghua.edu.cn/static/img/favicon.ico","filePath":"/data/storage/el2/base/haps/entry/files/selftest/dl_case.ico","headers":{"User-Agent":"Readest/1.0 (OPDS Browser)"}}' }
  ];

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    nativeBridge.setContextForTest(context);
    const initial: RowState[] = [];
    for (let i = 0; i < this.cases.length; i++) {
      initial.push({ result: '', running: false });
    }
    this.rows = initial;
  }

  async runOne(i: number): Promise<void> {
    const c: TestCase = this.cases[i];
    if (c.skip !== undefined) {
      this.rows[i] = { result: `SKIP: ${c.skip}`, running: false };
      return;
    }
    this.rows[i] = { result: '…', running: true };
    const out: string = await nativeBridge.testInvoke(c.cmd, c.args);
    const shown: string = out.length > 160 ? `${out.slice(0, 160)}…` : out;
    this.rows[i] = { result: shown, running: false };
  }

  async runAll(): Promise<void> {
    let ok: number = 0;
    let skipped: number = 0;
    for (let i = 0; i < this.cases.length; i++) {
      await this.runOne(i);
      if (this.rows[i].result.startsWith('SKIP')) {
        skipped++;
      } else if (!this.rows[i].result.startsWith('THROW')) {
        ok++;
      }
    }
    this.summary = `${ok}/${this.cases.length} 条非 THROW，${skipped} 条 SKIP（交互类）`;
  }

  build() {
    Column() {
      Text('Readest 鸿蒙 · 桥接自测页')
        .fontSize(18).fontWeight(FontWeight.Bold).padding(12)
      Text(this.summary).fontSize(13).fontColor('#666').padding({ bottom: 8 })
      Button('全部运行').onClick(() => {
        this.runAll();
      })
      Scroll() {
        Column() {
          ForEach(this.cases, (c: TestCase, i: number) => {
            Column() {
              Row() {
                Text(`[${c.group}] ${c.cmd}`)
                  .fontSize(12).fontWeight(FontWeight.Medium)
                  .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button(this.rows[i] && this.rows[i].running ? '…' : '运行')
                  .fontSize(12).height(28)
                  .onClick(() => {
                    this.runOne(i);
                  })
              }.width('100%')
              if (this.rows[i] && this.rows[i].result !== '') {
                Text(this.rows[i].result)
                  .fontSize(11).fontColor('#087ea4')
                  .width('100%').padding({ top: 2, bottom: 2 })
                  .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .width('100%')
            .padding(8)
            .border({ width: { bottom: 1 }, color: '#eee' })
          }, (c: TestCase) => c.cmd)
        }
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }
}
