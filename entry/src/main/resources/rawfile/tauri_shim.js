// Tauri v2 API shim for HarmonyOS (ArkWeb).
// Pretends to be window.__TAURI_INTERNALS__ so the unmodified readest frontend
// can run inside ArkWeb. All invoke() calls are forwarded to the ArkTS
// NativeBridge via window.__ohosBridge and resolved asynchronously.
(function () {
  'use strict';

  // Brand rename (2026-10-27, review feedback 9.5): the frontend sets
  // document.title dynamically ("Readest — ...") and ArkWeb mirrors it to the
  // PC window title bar. Intercept every title write and swap the brand so the
  // window bar never shows the upstream name.
  try {
    var titleDesc = Object.getOwnPropertyDescriptor(Document.prototype, 'title');
    if (titleDesc && titleDesc.set) {
      Object.defineProperty(document, 'title', {
        configurable: true,
        get: function () { return titleDesc.get.call(document); },
        set: function (v) {
          try { titleDesc.set.call(document, String(v).replace(/readest/gi, '\u9605\u6613\u9605\u8bfb\u5668')); }
          catch (e) { /* never block the page */ }
        }
      });
    }
  } catch (e) { /* older engines: fall back to natural behavior */ }

  try { console.log('[SHIM-LOAD]', (window.top === window ? 'main' : 'sub') + ':' +
    String(location.href).slice(-40)); } catch (e) { /* probe only */ }

  // ---- 华为账号一键登录按钮（登录页，审核建议项）----
  // /auth 路由下向登录面板追加「使用华为账号登录」按钮：点击经桥接拉起
  // Login Kit 系统授权弹窗（plugin:huawei-account|login），成功显示华为
  // 账号身份并持久化（localStorage.hwid_openid，重启后恢复已连接态）。
  // MutationObserver 等 React 渲染完成后插入，插入一次即断开。
  // 运行前置（缺一则报 1001500001）：module.json5 metadata.client_id =
  // AGC 应用 APP ID；AGC 项目设置 → SDK 配置已添加发布证书 SHA256 指纹。
  try {
    if (location.pathname.indexOf('/auth') === 0 &&
        typeof MutationObserver !== 'undefined') {
      var __hwDone = false;
      var __hwObserver = new MutationObserver(function () {
        if (__hwDone) return;
        var buttons = Array.prototype.filter.call(
          document.querySelectorAll('button'),
          function (b) { return b.textContent && b.textContent.indexOf('Discord') !== -1; });
        var ref = buttons[buttons.length - 1];
        if (!ref) return;
        __hwDone = true;
        __hwObserver.disconnect();
        var btn = ref.cloneNode(true);
        btn.id = 'hwid-login-btn';
        var span = btn.querySelector('span.line-clamp-1');
        if (!span) span = btn.querySelector('span');
        var setText = function (t) { if (span) span.textContent = t; };
        var iconEl = btn.querySelector('svg');
        if (iconEl) {
          var badge = document.createElement('span');
          badge.style.cssText = 'width:20px;height:20px;display:inline-flex;align-items:center;' +
            'justify-content:center;background:#CE0E2D;color:#fff;border-radius:4px;' +
            'font-size:12px;font-weight:bold;flex-shrink:0;';
          badge.textContent = '华';
          iconEl.replaceWith(badge);
        }
        // 会话恢复：此前登录成功过的设备直接回到已连接态（本地身份，
        // 无云后端——授权码不落 readest 云，见桥接端注释）
        var prevId = '';
        try { prevId = localStorage.getItem('hwid_openid') || ''; } catch (ePrev) {}
        if (prevId) {
          setText('已连接：' + prevId.slice(0, 10) + '…');
          btn.disabled = true;
        } else {
          setText('使用华为账号登录');
        }
        // 点击处理（独立函数：委托模式从被点节点现取 span，防 React 重渲染
        // 丢闭包引用）
        var handleHwidClick = function (t) {
          var sp = t.querySelector('span.line-clamp-1') || t.querySelector('span');
          var setT = function (x) { if (sp) sp.textContent = x; };
          setT('正在拉起华为账号…');
          window.__TAURI_INTERNALS__.invoke('plugin:huawei-account|login', {})
            .then(function (res) {
              if (res && res.success) {
                setT('已连接：' + String(res.openID || '').slice(0, 10) + '…');
                t.disabled = true;
                try { localStorage.setItem('hwid_openid', res.openID || ''); } catch (e2) {}
                try { window.dispatchEvent(new CustomEvent('hwid-login-success')); } catch (e2) {}
              } else if (res && res.cancelled) {
                setT('使用华为账号登录');
              } else {
                setT('使用华为账号登录');
                // 常见错误码翻译（Authentication Kit 错误码文档），其余透传
                var raw = String((res && res.error) || '未知错误');
                var m = raw.match(/code=(\d+)/);
                var code = m ? m[1] : '';
                var friendly = {
                  '1001500001': '应用签名指纹校验失败：需在 AGC 项目设置→SDK配置中添加发布证书指纹，并核对 client_id 配置',
                  '1001502001': '本机尚未登录华为账号：请在系统「设置→华为账号」登录后重试',
                  '1001502003': 'client_id 无效：请核对 AGC 项目设置中的 client_id 与应用是否开通账号服务'
                }[code];
                alert('华为账号登录失败：' + (friendly || raw));
              }
            }).catch(function (e3) {
              setT('使用华为账号登录');
              alert('华为账号登录失败：' + ((e3 && e3.message) || e3));
            });
        };
        // 事件委托（2026-11-11 模拟器实证：React 重渲染会替换克隆节点的
        // 监听器槽位，clone 时挂的 addEventListener 会静默丢失——改挂
        // document 捕获阶段，按 id 匹配，任意代 DOM 都能响应）
        document.addEventListener('click', function (ev) {
          var t = ev.target;
          while (t && t !== document.body) {
            if (t.id === 'hwid-login-btn') {
              if (t.disabled) return;
              handleHwidClick(t);
              return;
            }
            t = t.parentElement;
          }
        }, true);
        ref.parentNode.insertBefore(btn, ref.nextSibling);
      });
      __hwObserver.observe(document.documentElement, { childList: true, subtree: true });
      document.addEventListener('DOMContentLoaded', function () { __hwObserver.takeRecords(); });
    }
  } catch (e) { /* never block the page */ }

  // ---- 邮箱认证表单隐藏（五轮审核问题2；2026-11-18）----
  // 上游账号体系=Supabase 海外后端：注册验证邮件内的确认链接域名在大陆
  // 网络不可达（审核实测"点击邮件内地址无法访问"），客户端不可修。隐藏
  // 邮箱登录/注册入口（保留第三方按钮+华为账号登录），消除不可用功能面。
  try {
    if (location.pathname.indexOf('/auth') === 0) {
      var __hideEmail = function () {
        var divider = null;
        var spans = document.querySelectorAll('span, p, div, h2, h3');
        for (var i = 0; i < spans.length; i++) {
          var t = (spans[i].textContent || '').replace(/\s+/g, ' ').trim();
          if (t === '或使用邮箱继续' || t === 'Or continue with email' ||
              t === '继续输入邮箱' || t.toLowerCase() === 'continue with email') {
            divider = spans[i];
            break;
          }
        }
        if (!divider || divider.getAttribute('data-email-hidden')) return;
        divider.setAttribute('data-email-hidden', '1');
        // 从分隔文案起，隐藏其所在的后续表单区块（向上找一个合理的容器）
        var container = divider.parentElement;
        for (var up = 0; up < 4 && container && container !== document.body; up++) {
          if (container.nextElementSibling || container.children.length > 1) break;
          container = container.parentElement;
        }
        var node = divider.closest('form') || container || divider.parentElement;
        var el = divider;
        // 隐藏 divider 之后的所有兄弟节点（邮箱输入/登录/魔法链接/注册）
        while (el) {
          var next = el.nextElementSibling;
          el.style.display = 'none';
          el = next;
        }
        divider.style.display = 'none';
      };
      var __emailObs = new MutationObserver(function () { __hideEmail(); });
      __emailObs.observe(document.documentElement, { childList: true, subtree: true });
      document.addEventListener('DOMContentLoaded', function () { __hideEmail(); });
    }
  } catch (e) { /* never block the page */ }

  // Upstream "self-hosted distribution" posture: this build ships without the
  // vendor's cloud/payment backend, so unlock the features the paywall gates
  // (isSelfHosted() in src/utils/access.ts reads this window key) — otherwise
  // the Premium upsell points at a backend this fork does not run.
  try {
    window.__READEST_RUNTIME_CONFIG =
      Object.assign({}, window.__READEST_RUNTIME_CONFIG, { selfHosted: true });
  } catch (e) { /* never block the page */ }

  // （审计移除）D12 的 iframe getter 转发块——真机 KI-5 实际由全 shell
  // 加固+缓存绕过（同批部署）治愈；本块反而破坏 Chromium 系 lab 渲染
  // （reader 探针挂起于"加载中"，A/B 定位 2026-10-24），且对 ArkWeb 属
  // 高危 defineProperty 面。两环境统一为无此块版本。

  // D14 偏差④整改：Worker 防线移除评估——原预防线（全局禁用 Worker）
  // 为虚拟主机 worker 加载未验证的保守措施；真机实测 pdf.js worker 经
  // onInterceptRequest 可用后应移除。当前状态：已重新启用（见
  // FINAL-VERIFICATION 偏差④整改记录）。若 PDF 出现 worker 加载失败，
  // pdf.js 自带 fake-worker 主线程回退（此前全格式验证即该路径）。


  var pending = new Map();      // reqId -> {resolve, reject}
  var transformCbs = new Map(); // cbId  -> callback (Tauri event transform callbacks)
  var eventTargets = new Map(); // eventName -> Set<cbId>
  var reqSeq = 1;
  var cbSeq = 1;

  // Uint8Array/ArrayBuffer → base64（分块，防大文件 String.fromCharCode 栈溢出；
  // 与桥端 util.Base64Helper.decodeSync 配对）
  function bytesToB64(input) {
    var u8 = input instanceof ArrayBuffer ? new Uint8Array(input) : input;
    var binary = '';
    for (var i = 0; i < u8.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    }
    return btoa(binary);
  }

  function jsonSafe(v, fallback) {
    try { return JSON.stringify(v); } catch (e) { return fallback; }
  }

  // ---- event bus (plugin:event|* handled locally, native can push too) ----
  function deliverEvent(cbId, payloadJson) {
    var cb = transformCbs.get(cbId);
    if (cb) {
      try { cb(JSON.parse(payloadJson)); } catch (e) { cb(payloadJson); }
    }
  }
  window.__deliverEvent = deliverEvent;

  function localListen(event, cbId) {
    if (!eventTargets.has(event)) eventTargets.set(event, new Set());
    eventTargets.get(event).add(cbId);
  }
  function localUnlisten(event, cbId) {
    var s = eventTargets.get(event);
    if (s) { s.delete(cbId); if (s.size === 0) eventTargets.delete(event); }
  }
  function localEmit(event, payloadJson) {
    var s = eventTargets.get(event);
    if (!s) return;
    s.forEach(function (cbId) { deliverEvent(cbId, payloadJson); });
  }
  // native-side push entry (device: NativeBridge runJavaScript; lab: mock) —
  // plugin listeners listen as 'plugin:<plugin>|<event>'
  window.__shimEmitEvent = localEmit;

  // ---- core invoke ----
  function invoke(cmd, args, options) {
    args = args || {};

    // Event plugin: fully local pub/sub, never crosses the bridge.
    if (cmd === 'plugin:event|listen') {
      var cbId = args.handler;
      if (typeof cbId === 'number') localListen(args.event, cbId);
      return Promise.resolve(Number(reqSeq++));
    }
    if (cmd === 'plugin:event|unlisten') {
      if (typeof args.eventId === 'number') {
        // we don't track event->id mapping; unlisten by handler id instead
      }
      if (args.handler !== undefined) localUnlisten(args.event, args.handler);
      return Promise.resolve();
    }
    if (cmd === 'plugin:event|emit') {
      localEmit(args.event, jsonSafe(args.payload || null, 'null'));
      // also let native observe emits (e.g. to sync UI state)
      try { window.__ohosBridge.notify(cmd, jsonSafe(args, '{}')); } catch (e) { /* bridge absent in plain browser dev */ }
      return Promise.resolve();
    }

    // Plugin version queries: pretend to be the versions readest expects.
    if (cmd === 'plugin:os|platform') return Promise.resolve('android');
    if (cmd === 'plugin:os|family') return Promise.resolve('mobile');
    if (cmd === 'plugin:os|version') return Promise.resolve('14');
    if (cmd === 'plugin:os|arch') return Promise.resolve('aarch64');
    if (cmd === 'plugin:os|type') return Promise.resolve('linux');
    if (cmd === 'plugin:os|locale') return Promise.resolve(navigatorLanguage());
    if (cmd === 'plugin:os|hostname') return Promise.resolve('readest-ohos');
    if (cmd === 'plugin:window|version' || cmd === 'plugin:event|version' ||
        cmd === 'plugin:path|version' || cmd === 'plugin:os|version') {
      return Promise.resolve('2.0.0');
    }

    return new Promise(function (resolve, reject) {
      var id = reqSeq++;
      pending.set(id, { resolve: resolve, reject: reject });
      // 写命令的二进制 body → base64 包装（三/四/五轮审核 TXT 'File is
      // empty' 真凶实锤：plugin-fs writeFile 把 File 对象原样作 invoke body，
      // JSON.stringify(File)='{}' → 桥收到空映射 → 静默 0 字节落盘 → 导入
      // "成功"建卡、开书 File is empty。File/Blob/TypedArray 全形态归一为
      // base64 字符串（跨引擎序列化一致）；桥端 fsExtractBytes 识别并解码，
      // 旧字节映射形态保留兼容。）
      var headersJson = 'null';
      try {
        if (options && options.headers) { headersJson = JSON.stringify(options.headers); }
      } catch (e) { /* headers stay null */ }
      (async function () {
        var payload;
        try {
          if ((cmd === 'plugin:fs|write_file' || cmd === 'plugin:fs|write_text_file') &&
              args && typeof args === 'object') {
            var u8 = null;
            if (typeof Blob !== 'undefined' && args instanceof Blob) {
              u8 = new Uint8Array(await args.arrayBuffer());
            } else if (typeof args.byteLength === 'number') {
              u8 = args;
            } else if (args instanceof ArrayBuffer) {
              u8 = new Uint8Array(args);
            }
            if (u8 !== null) {
              payload = JSON.stringify({ __b64: bytesToB64(u8) });
            } else {
              payload = JSON.stringify(args);
            }
          } else {
            payload = JSON.stringify(args);
          }
          window.__ohosBridge.invoke(cmd, id, payload, headersJson);
        } catch (e) {
          pending.delete(id);
          reject(new Error('bridge unavailable: ' + cmd));
        }
      })();
    });
  }

  function navigatorLanguage() {
    var l = (navigator.language || 'en').toLowerCase();
    return l;
  }

  // ---- Tauri internals contract (subset used by @tauri-apps/api v2) ----
  window.__TAURI_INTERNALS__ = {
    invoke: invoke,
    transformCallback: function (callback, once) {
      var id = cbSeq++;
      transformCbs.set(id, function (payload) {
        if (once) transformCbs.delete(id);
        callback(payload);
      });
      return id;
    },
    convertFileSrc: function (filePath, protocol) {
      protocol = protocol || 'asset';
      return 'http://readest.ohos.internal/' + protocol + '/' + encodeURIComponent(filePath);
    },
    metadata: {
      currentWindow: { label: 'main' },
      currentWebview: { label: 'main' },
      windows: ['main'],
      webviews: ['main']
    },
    plugins: {}
  };

  // ---- resolution entrypoints called from ArkTS ----
  window.__shimResolve = function (id, ok, json) {
    id = Number(id);
    var entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    if (ok) {
      var value;
      try { value = JSON.parse(json); } catch (e) { value = json; }
      entry.resolve(value);
    } else {
      entry.reject(new Error(json));
    }
  };

  // Injected-globals contract discovered from the built bundle (browser lab):
  // the bundled @tauri-apps plugins read these synchronously at module init.
  // Missing any of them kills app-service init with a silent TypeError.
  window.__TAURI_OS_PLUGIN_INTERNALS__ = {
    arch: 'aarch64',
    // D12：设备是 HarmonyOS PC（MateBook）——按 windows 语义走桌面分支。
    // readest 的 openFile 对 android 走 RemoteFile（rangefile Range 请求），
    // 对 windows 直接走 NativeFile（fs|open/fstat——本 bridge 已实现且验证）。
    os_type: 'windows',
    version: '14'
  };
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
    // event bus is local in this shim; native-side unlisten is a no-op
    unregisterListener: function (eventId, handler) { /* no-op */ }
  };
  window.__TAURI_TO_IPC_KEY__ = function (key) { return key; };

  // Minimal platform detection fallbacks some libs probe before internals exist.
  window.__TAURI__ = window.__TAURI__ || {};
  window.__TAURI_OS_PLUGIN_2__ = window.__TAURI_OS_PLUGIN_2__ || {};
})();
