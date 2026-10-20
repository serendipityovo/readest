// Tauri v2 API shim for HarmonyOS (ArkWeb).
// Pretends to be window.__TAURI_INTERNALS__ so the unmodified readest frontend
// can run inside ArkWeb. All invoke() calls are forwarded to the ArkTS
// NativeBridge via window.__ohosBridge and resolved asynchronously.
(function () {
  'use strict';

  // OHOS 预防线：ArkWeb 下 worker 脚本请求可能不经过 onInterceptRequest（未验证）。
  // 库搜索与 pdf.js 均有主线程回退（librarySearchWorker.ts 的 searchOnMainThread、
  // pdfjs 的 fake worker），故全局禁用 Worker 零成本规避。
  // TODO(D12): 真机验证 pdf.js worker 经虚拟主机可用后，移除此行恢复多线程性能。
  window.Worker = undefined;

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
    os_type: 'android',
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
