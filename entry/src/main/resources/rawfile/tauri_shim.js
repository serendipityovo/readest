// Tauri v2 API shim for HarmonyOS (ArkWeb).
// Pretends to be window.__TAURI_INTERNALS__ so the unmodified readest frontend
// can run inside ArkWeb. All invoke() calls are forwarded to the ArkTS
// NativeBridge via window.__ohosBridge and resolved asynchronously.
(function () {
  'use strict';

  try { console.log('[SHIM-LOAD]', (window.top === window ? 'main' : 'sub') + ':' +
    String(location.href).slice(-40)); } catch (e) { /* probe only */ }

  // KI-5 残余修复（D12）：同源 iframe（foliate paginator、filter iframe）
  // 不继承主文档 <head> 注入。注意：shim 主体在 IIFE 后段才给 internals
  // 赋完整值且是整体重赋——若此处直接转发对象引用，iframe 会持有早期空
  // 对象且不再更新。故用 getter 转发（每次读取取主 window 最新值）。
  try {
    var injectIntoFrame = function (f) {
      try {
        var w = f.contentWindow;
        if (!w || w.__KI5_ARMED__) return;
        try {
          w.__KI5_ARMED__ = true;
          var keys = ['__TAURI_INTERNALS__', '__TAURI_OS_PLUGIN_INTERNALS__',
                      '__TAURI_OS_PLUGIN_2__', '__TAURI_EVENT_PLUGIN_INTERNALS__',
                      '__TAURI_TO_IPC_KEY__'];
          for (var i = 0; i < keys.length; i++) {
            (function (k) {
              try {
                Object.defineProperty(w, k, {
                  configurable: true,
                  get: function () { return window[k]; },
                  set: function (v) { try { window[k] = v; } catch (e) { /* ro */ } }
                });
              } catch (e) { /* already defined */ }
            })(keys[i]);
          }
        } catch (e) { /* define failed */ }
      } catch (e) { /* sandboxed cross-origin frame: skip */ }
    };
    var armFrame = function (n) {
      injectIntoFrame(n);
      try { n.addEventListener('load', function () { injectIntoFrame(n); }, { once: true }); }
      catch (e) { /* detached */ }
    };
    var mo = new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var add = muts[i].addedNodes;
        for (var j = 0; j < add.length; j++) {
          var n = add[j];
          if (n && n.tagName === 'IFRAME') armFrame(n);
        }
      }
    });
    mo.observe(document.documentElement || document, { childList: true, subtree: true });
    var existing = document.querySelectorAll('iframe');
    for (var k = 0; k < existing.length; k++) armFrame(existing[k]);
  } catch (e) { /* engine without MutationObserver */ }

  // D14 偏差④整改：Worker 防线移除评估——原预防线（全局禁用 Worker）
  // 为虚拟主机 worker 加载未验证的保守措施；真机实测 pdf.js worker 经
  // onInterceptRequest 可用后应移除。当前状态：已重新启用（见
  // FINAL-VERIFICATION 偏差④整改记录）。若 PDF 出现 worker 加载失败，
  // pdf.js 自带 fake-worker 主线程回退（此前全格式验证即该路径）。
  // window.Worker = undefined;

  var pending = new Map();      // reqId -> {resolve, reject}
  var transformCbs = new Map(); // cbId  -> callback (Tauri event transform callbacks)
  var eventTargets = new Map(); // eventName -> Set<cbId>
  var reqSeq = 1;
  var cbSeq = 1;

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
      var payload;
      try { payload = JSON.stringify(args); } catch (e) { payload = '{}'; }
      // Tauri v2 fs write protocol: contents travel as the invoke BODY (raw
      // bytes) while path/options ride in options.headers (path URL-encoded).
      // The bridge needs both to reconstruct the call.
      var headersJson = 'null';
      try {
        if (options && options.headers) { headersJson = JSON.stringify(options.headers); }
      } catch (e) { /* headers stay null */ }
      try {
        window.__ohosBridge.invoke(cmd, id, payload, headersJson);
      } catch (e) {
        pending.delete(id);
        reject(new Error('bridge unavailable: ' + cmd));
      }
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
