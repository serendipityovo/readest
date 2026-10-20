// Browser-lab mock of the ArkTS __ohosBridge: lets the readest frontend run
// in a desktop Chromium for device-free validation. Mirrors the contract in
// tauri_shim.js (invoke -> __shimResolve) and records every command into
// window.__census for the invoke census.
//
// Includes a localStorage-backed virtual file system implementing the
// plugin:fs family with Tauri semantics (arg shapes captured from the real
// census: read/write take {path, contents, options:{baseDir:number}},
// resolve_directory takes {directory:number} = BaseDirectory enum).
(function () {
  'use strict';

  window.__census = [];
  var labChannels = {}; // plugin-listener events -> Channel transformCallback id
  var labChannelSeq = {}; // per-channel monotonic message index (Tauri Channel ordering)
  // D8 network passthrough state
  var labWs = {}; // wsId -> {sock, ch, open}
  var labWsSeq = 0;
  var labHttp = {}; // rid -> Promise<responseInfo>
  var labHttpSeq = 0;
  var labHttpBodies = {}; // rid -> number[]
  // deliver to a DIRECT Channel id (per-call arg, e.g. websocket onMessage) with
  // the same monotonic-index ordering contract as pushChannel
  function labDeliverDirect(channelId, message) {
    var idx = labChannelSeq[channelId] || 0;
    labChannelSeq[channelId] = idx + 1;
    try {
      window.__deliverEvent(channelId, JSON.stringify({ index: idx, message: message }));
    } catch (e) { /* page gone */ }
  }

  // ---- BaseDirectory enum (@tauri-apps/api path.d.ts) ----
  var BASE_DIRS = {
    1: 'Audio', 2: 'Cache', 3: 'Config', 4: 'Data', 5: 'LocalData',
    6: 'Document', 7: 'Download', 8: 'Picture', 9: 'Public', 10: 'Video',
    11: 'Resource', 12: 'Temp', 13: 'AppConfig', 14: 'AppData',
    15: 'AppLocalData', 16: 'AppCache', 17: 'AppLog', 18: 'Desktop',
    19: 'Executable', 20: 'Font', 21: 'Home', 22: 'Runtime', 23: 'Template'
  };
  var BUNDLE = 'com.readest.app';
  // mirrors NativeBridge.ets baseDirByEnum: all app dirs -> /lab/files
  var ROOTS = {
    13: '/lab/files',
    14: '/lab/files',
    15: '/lab/files',
    16: '/lab/cache',
    17: '/lab/files/logs',
    19: '/lab/files'
  };
  function baseDirPath(n) {
    if (ROOTS[n]) return ROOTS[n];
    return '/lab/' + ((BASE_DIRS[n] || 'base' + n)).toLowerCase();
  }

  // ---- virtual FS in localStorage (survives reload == app restart) ----
  function loadFiles() {
    try { return JSON.parse(localStorage.getItem('labfs_files') || '{}'); }
    catch (e) { return {}; }
  }
  function saveFiles(f) {
    try { localStorage.setItem('labfs_files', JSON.stringify(f)); } catch (e) { /* keep going */ }
  }
  function loadDirs() {
    try { return JSON.parse(localStorage.getItem('labfs_dirs') || '[]'); }
    catch (e) { return []; }
  }
  function saveDirs(d) {
    try { localStorage.setItem('labfs_dirs', JSON.stringify(d)); } catch (e) { /* keep going */ }
  }
  function resolvePath(args) {
    var p = String((args && args.path) || '');
    var base = args && args.options && typeof args.options.baseDir === 'number'
      ? args.options.baseDir : null;
    var abs = (base !== null && p.charAt(0) !== '/')
      ? baseDirPath(base) + '/' + p
      : p;
    return abs.replace(/\/+/g, '/').replace(/\/$/, '') || '/';
  }
  // byte-map -> byte array (numeric keys ascending); strict UTF-8 decode that
  // THROWS on binary content (epub/zip): round-trip against TextEncoder decides
  // text vs binary storage — binary lands in the {__b64} channel
  function byteMapBytes(c) {
    var keys = Object.keys(c).filter(function (k) { return /^\d+$/.test(k); })
      .map(Number).sort(function (a, b) { return a - b; });
    return keys.map(function (k) { return c[k] & 0xFF; });
  }
  function utf8DecodeStrict(bytes) {
    var out = '';
    var i = 0;
    while (i < bytes.length) {
      var b = bytes[i];
      var cp = b, len = 1;
      if (b < 0x80) { cp = b; }
      else if (b < 0xC0) { throw new Error('bad utf8 continuation'); }
      else if (b < 0xE0) { cp = b & 0x1F; len = 2; }
      else if (b < 0xF0) { cp = b & 0x0F; len = 3; }
      else { cp = b & 0x07; len = 4; }
      if (i + len > bytes.length) throw new Error('truncated utf8');
      for (var j = 1; j < len; j++) cp = (cp * 64) + (bytes[i + j] & 0x3F);
      if (cp > 0x10FFFF) throw new Error('bad code point');
      out += String.fromCodePoint(cp);
      i += len;
    }
    return out;
  }
  function bytesToB64(bytes) {
    var s = '';
    for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s);
  }
  function decodeForStore(c) {
    if (typeof c === 'string') return { text: c };
    if (c && typeof c === 'object') {
      var bytes = byteMapBytes(c);
      try {
        var text = utf8DecodeStrict(bytes);
        var re = new TextEncoder().encode(text);
        var ok = re.length === bytes.length;
        if (ok) {
          for (var i = 0; i < bytes.length; i++) {
            if (re[i] !== bytes[i]) { ok = false; break; }
          }
        }
        if (ok) return { text: text };
      } catch (e) { /* binary: fall through */ }
      return { b64: bytesToB64(bytes) };
    }
    return { text: '' };
  }
  function decodeContents(c) {
    var d = decodeForStore(c);
    return d.b64 !== undefined ? d.b64 : d.text;
  }
  window.__fsDump = function () {
    return JSON.stringify({ files: loadFiles(), dirs: loadDirs() }, null, 1);
  };

  // ---- lab equivalent of the device-side onInterceptRequest book host:
  //      fetch() of http://readest.ohos.internal/<path> (what convertFileSrc
  //      produces in the shim) is served from the virtual FS, binary aware.
  function bookMime(p) {
    if (/\.epub$/i.test(p)) return 'application/epub+zip';
    if (/\.pdf$/i.test(p)) return 'application/pdf';
    if (/\.html?$/i.test(p)) return 'text/html';
    if (/\.css$/i.test(p)) return 'text/css';
    if (/\.js$/i.test(p)) return 'text/javascript';
    if (/\.png$/i.test(p)) return 'image/png';
    if (/\.jpe?g$/i.test(p)) return 'image/jpeg';
    if (/\.svg$/i.test(p)) return 'image/svg+xml';
    if (/\.woff2?$/i.test(p)) return 'font/woff';
    if (/\.ttf$/i.test(p)) return 'font/ttf';
    return 'application/octet-stream';
  }
  function labFileBytes(p) {
    var files = loadFiles();
    if (!Object.prototype.hasOwnProperty.call(files, p)) {
      return null;
    }
    var v = files[p];
    if (v && typeof v === 'object' && typeof v.__b64 === 'string') {
      var bin = atob(v.__b64);
      var u8 = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
      return u8;
    }
    return new TextEncoder().encode(String(v));
  }
  function serveLabPath(p) {
    var bytes = labFileBytes(p);
    if (bytes === null) {
      return Promise.resolve(new Response('not found: ' + p, { status: 404 }));
    }
    return Promise.resolve(new Response(bytes, {
      status: 200,
      headers: { 'Content-Type': bookMime(p) }
    }));
  }
  // rangefile query-range protocol (RemoteFile.fromNativePath, Android path):
  // ?path=<abs>&start=<s>&end=<e> (inclusive) with the total size in X-Total-Size
  function serveRangeFile(url) {
    var q = {};
    url.split('?')[1].split('&').forEach(function (kv) {
      var pair = kv.split('=');
      q[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1] || '');
    });
    var p = q.path || '';
    var bytes = labFileBytes(p);
    if (bytes === null) {
      return Promise.resolve(new Response('not found: ' + p, { status: 404 }));
    }
    var start = q.start !== undefined ? Math.max(0, parseInt(q.start, 10) || 0) : 0;
    var end = q.end !== undefined ? Math.min(bytes.length - 1, parseInt(q.end, 10) || 0) : bytes.length - 1;
    if (end < start) end = start;
    var slice = bytes.slice(start, end + 1);
    return Promise.resolve(new Response(slice, {
      status: 200,
      headers: {
        'Content-Type': bookMime(p),
        'X-Total-Size': String(bytes.length)
      }
    }));
  }
  var INTERNAL_HOST = 'http://readest.ohos.internal/';
  var RANGE_HOST = 'http://rangefile.localhost/';
  var origFetch = window.fetch ? window.fetch.bind(window) : null;
  if (origFetch) {
    window.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || String(input);
      if (url.indexOf(INTERNAL_HOST) === 0) {
        var rel = decodeURIComponent(url.slice(INTERNAL_HOST.length)).split('?')[0];
        rel = rel.replace(/^\/+/, '');
        if (rel.indexOf('asset/') === 0) rel = rel.slice(6); // asset-protocol style: /asset/<encoded-abs>
        return serveLabPath('/' + rel);
      }
      if (url.indexOf(RANGE_HOST) === 0) {
        return serveRangeFile(url);
      }
      return origFetch(input, init);
    };
  }

  // ---- mini-SQL engine (lab turso backend) ----
  // The real @readest/turso-database-wasm is a wasi-threads build that hard
  // requires SharedArrayBuffer isolation; the IAB view is never isolated and
  // headless --virtual-time-budget does not wait for dedicated workers (both
  // probed 2026-10-15). This engine implements readest's ACTUAL statement
  // surface instead — evidence: services/database/migrations/, migrate.ts,
  // librarySearchIndex.ts, dictionaries/plugins/*, bookorbit stores. Books and
  // reading progress themselves live in settings.json (fs layer, not turso).
  function dbLoad(name) {
    try {
      return JSON.parse(localStorage.getItem('labdb_' + name) || 'null')
        || { tables: {}, userVersion: 0, seq: {} };
    } catch (e) { return { tables: {}, userVersion: 0, seq: {} }; }
  }
  function dbSave(name, state) {
    try { localStorage.setItem('labdb_' + name, JSON.stringify(state)); } catch (e) { /* keep going */ }
  }
  function dbClone(state) { return JSON.parse(JSON.stringify(state)); }

  // tokenizer: 'str' ('' escape), numbers, $N params, identifiers, operators
  // every token carries its source start offset `s` (scalar-subquery capture)
  function sqlTokens(s) {
    var toks = [];
    var i = 0;
    while (i < s.length) {
      var c = s.charAt(i);
      var s0 = i;
      if (/\s/.test(c)) { i++; continue; }
      if (c === "'") {
        var j = i + 1, str = '';
        while (j < s.length) {
          if (s.charAt(j) === "'" && s.charAt(j + 1) === "'") { str += "'"; j += 2; continue; }
          if (s.charAt(j) === "'") break;
          str += s.charAt(j); j++;
        }
        toks.push({ t: 'str', v: str, s: s0 });
        i = j + 1; continue;
      }
      if (/[0-9]/.test(c) || (c === '-' && /[0-9]/.test(s.charAt(i + 1) || ''))) {
        var k = i + 1;
        while (k < s.length && /[0-9.]/.test(s.charAt(k))) k++;
        toks.push({ t: 'num', v: parseFloat(s.slice(i, k)), s: s0 });
        i = k; continue;
      }
      if (/[A-Za-z_$]/.test(c)) {
        var m = i;
        while (m < s.length && /[A-Za-z0-9_$]/.test(s.charAt(m))) m++;
        var word = s.slice(i, m);
        if (/^\$\d+$/.test(word)) toks.push({ t: 'param', v: parseInt(word.slice(1), 10) - 1, s: s0 });
        else toks.push({ t: 'id', v: word, s: s0 });
        i = m; continue;
      }
      var two = s.substr(i, 2);
      if (two === '>=' || two === '<=' || two === '<>' || two === '!=' || two === '||') {
        toks.push({ t: 'op', v: two, s: s0 }); i += 2; continue;
      }
      if (c === '?') { toks.push({ t: 'q', v: 0, s: s0 }); i++; continue; }
      toks.push({ t: 'op', v: c, s: s0 });
      i++;
    }
    return toks;
  }

  // recursive-descent WHERE/value expression parser
  // node kinds: lit/param/col/coalesce/not/and/or/cmp/isnull/in/like/add/mul/fn/subq
  // qctx: per-STATEMENT bare-'?' counter (SQLite numbers ? across the whole
  // statement, so SET and WHERE clauses must share one counter)
  function ExprParser(toks, qctx, src) {
    var pos = 0;
    function peek() { return toks[pos]; }
    function kw(t) {
      var p = peek();
      return p && p.t === 'id' && p.v.toUpperCase() === t;
    }
    function eat(t, v) {
      var p = peek();
      if (!p) throw new Error('mini-sql: unexpected end');
      if (p.t === t && (v === undefined || p.v === v || String(p.v).toUpperCase() === String(v).toUpperCase())) {
        pos++; return p;
      }
      throw new Error('mini-sql: expected ' + (v || t) + ' got ' + JSON.stringify(p));
    }
    function parse() {
      var e = orExpr();
      if (pos < toks.length) throw new Error('mini-sql: trailing tokens');
      return e;
    }
    function orExpr() {
      var l = andExpr();
      while (kw('OR')) { pos++; l = { k: 'or', l: l, r: andExpr() }; }
      return l;
    }
    function andExpr() {
      var l = notExpr();
      while (kw('AND')) { pos++; l = { k: 'and', l: l, r: notExpr() }; }
      return l;
    }
    function notExpr() {
      if (kw('NOT')) { pos++; return { k: 'not', e: notExpr() }; }
      return cmp();
    }
    function cmp() {
      var l = addExpr();
      var p = peek();
      if (p && p.t === 'op' && ['=', '!=', '<>', '<', '<=', '>', '>='].indexOf(p.v) >= 0) {
        pos++;
        return { k: 'cmp', op: p.v, l: l, r: addExpr() };
      }
      if (kw('IS')) {
        pos++;
        var neg = false;
        if (kw('NOT')) { pos++; neg = true; }
        eat('id', 'NULL');
        return { k: 'isnull', e: l, neg: neg };
      }
      var negLike = false;
      if (kw('NOT')) { pos++; negLike = true; }
      if (kw('LIKE')) {
        pos++;
        var pat = primary();
        var esc = null;
        if (kw('ESCAPE')) { pos++; esc = primary(); }
        return { k: 'like', e: l, pat: pat, esc: esc, neg: negLike };
      }
      if (kw('IN')) {
        pos++;
        eat('op', '(');
        var list = [];
        while (true) {
          list.push(primary());
          if (peek() && peek().t === 'op' && peek().v === ',') { pos++; continue; }
          break;
        }
        eat('op', ')');
        return { k: 'in', e: l, list: list, neg: negLike };
      }
      if (negLike) throw new Error('mini-sql: NOT without LIKE/IN');
      return l;
    }
    function addExpr() {
      var l = mulExpr();
      while (peek() && peek().t === 'op' && ['+', '-', '||'].indexOf(peek().v) >= 0) {
        var op = toks[pos++].v;
        l = { k: 'add', op: op, l: l, r: mulExpr() };
      }
      return l;
    }
    function mulExpr() {
      var l = primary();
      while (peek() && peek().t === 'op' && ['*', '/', '%'].indexOf(peek().v) >= 0) {
        var op = toks[pos++].v;
        l = { k: 'mul', op: op, l: l, r: primary() };
      }
      return l;
    }
    function primary() {
      var p = peek();
      if (!p) throw new Error('mini-sql: unexpected end');
      if (p.t === 'op' && p.v === '(') {
        // scalar subquery: (SELECT ... ) — capture raw source text and reserve
        // the ?s it contains in statement order (SQLite numbers placeholders
        // by appearance, and the subquery appears before any trailing WHERE)
        var nxt = toks[pos + 1];
        if (nxt && nxt.t === 'id' && nxt.v.toUpperCase() === 'SELECT') {
          if (!src) throw new Error('mini-sql: subquery requires source string');
          var depth = 1;
          var j = pos + 1;
          while (j < toks.length && depth > 0) {
            var tj = toks[j];
            if (tj.t === 'op' && tj.v === '(') depth++;
            else if (tj.t === 'op' && tj.v === ')') depth--;
            if (depth === 0) break;
            j++;
          }
          if (depth !== 0) throw new Error('mini-sql: unterminated subquery');
          var subSql = src.slice(p.s + 1, toks[j].s);
          var base = qctx.n;
          qctx.n += sqlTokens(subSql).filter(function (t2) { return t2.t === 'q'; }).length;
          pos = j + 1;
          return { k: 'subq', sql: subSql, base: base };
        }
        pos++;
        var e = orExpr();
        eat('op', ')');
        return e;
      }
      if (p.t === 'str') { pos++; return { k: 'lit', v: p.v }; }
      if (p.t === 'num') { pos++; return { k: 'lit', v: p.v }; }
      if (p.t === 'param') { pos++; return { k: 'param', i: p.v }; }
      if (p.t === 'q') { pos++; return { k: 'param', i: qctx.n++ }; }
      if (p.t === 'id') {
        var up = p.v.toUpperCase();
        if (up === 'NULL') { pos++; return { k: 'lit', v: null }; }
        if (up === 'COALESCE') {
          pos++;
          eat('op', '(');
          var args = [orExpr()];
          while (peek() && peek().t === 'op' && peek().v === ',') { pos++; args.push(orExpr()); }
          eat('op', ')');
          return { k: 'coalesce', args: args };
        }
        // scalar max(a,b)/min(a,b) — SQLite multi-arg form; NULL if any arg NULL
        if ((up === 'MAX' || up === 'MIN') && toks[pos + 1] && toks[pos + 1].t === 'op' && toks[pos + 1].v === '(') {
          pos += 2;
          var fargs = [orExpr()];
          while (peek() && peek().t === 'op' && peek().v === ',') { pos++; fargs.push(orExpr()); }
          eat('op', ')');
          return { k: 'fn', f: up.toLowerCase(), args: fargs };
        }
        if (up === 'EXCLUDED') {
          pos++;
          eat('op', '.');
          var col = eat('id').v;
          return { k: 'col', n: col, excluded: true };
        }
        pos++;
        return { k: 'col', n: p.v };
      }
      throw new Error('mini-sql: unexpected token ' + JSON.stringify(p));
    }
    this.parse = parse;
  }
  function parseExprTokens(toks, qctx, src) { return new ExprParser(toks, qctx || { n: 0 }, src).parse(); }
  function parseExprStr(s, qctx) { return parseExprTokens(sqlTokens(s), qctx, s); }

  function truthy(v) { return v === true || (typeof v === 'number' && v !== 0) || (typeof v === 'string' && v !== '' && v !== '0'); }
  // the state of the statement currently executing — scalar subqueries run
  // against it; set by sqlExec on entry (synchronous, no interleaving)
  var curDbState = null;
  function evalExpr(node, row, params, exRow) {
    switch (node.k) {
      case 'lit': return node.v;
      case 'param': return params !== undefined && params[node.i] !== undefined ? params[node.i] : null;
      case 'col':
        // upsert SET context: bare column = the EXISTING row, excluded.X = the
        // NEW row (exRow); elsewhere exRow is unset and both read `row`
        if (node.excluded && exRow !== undefined) {
          return Object.prototype.hasOwnProperty.call(exRow, node.n) ? exRow[node.n] : null;
        }
        return row !== undefined && Object.prototype.hasOwnProperty.call(row, node.n) ? row[node.n] : null;
      case 'add': {
        var al = evalExpr(node.l, row, params, exRow);
        var ar = evalExpr(node.r, row, params, exRow);
        if (node.op === '||') {
          var cs = (al === null || al === undefined ? '' : String(al)) + (ar === null || ar === undefined ? '' : String(ar));
          return cs === '' ? null : cs;
        }
        // SQLite: any NULL operand makes the arithmetic NULL
        if (al === null || al === undefined || ar === null || ar === undefined) return null;
        if (node.op === '+') return Number(al) + Number(ar);
        if (node.op === '-') return Number(al) - Number(ar);
        return null;
      }
      case 'mul': {
        var ml = evalExpr(node.l, row, params, exRow);
        var mr = evalExpr(node.r, row, params, exRow);
        if (ml === null || ml === undefined || mr === null || mr === undefined) return null;
        if (node.op === '*') return Number(ml) * Number(mr);
        if (node.op === '/') return Number(mr) === 0 ? null : Number(ml) / Number(mr);
        if (node.op === '%') return Number(mr) === 0 ? null : Number(ml) % Number(mr);
        return null;
      }
      case 'fn': {
        // scalar max()/min(): NULL if ANY argument is NULL (SQLite semantics)
        var best = null;
        for (var fi = 0; fi < node.args.length; fi++) {
          var fv = evalExpr(node.args[fi], row, params, exRow);
          if (fv === null || fv === undefined) return null;
          if (best === null) { best = fv; continue; }
          var lt = typeof fv === 'number' && typeof best === 'number' ? fv < best : String(fv) < String(best);
          if (node.f === 'max' ? !lt : lt) best = fv;
        }
        return best;
      }
      case 'subq': {
        // scalar subquery: re-execute the captured SELECT against the current
        // db with the params slice starting at the placeholder base reserved
        // at parse time (statement-order numbering)
        if (!curDbState) return null;
        var sub = sqlExec(curDbState, node.sql, params ? params.slice(node.base) : params);
        var r0 = sub && sub.rows && sub.rows[0];
        if (!r0) return null;
        for (var key in r0) { if (Object.prototype.hasOwnProperty.call(r0, key)) return r0[key]; }
        return null;
      }
      case 'coalesce':
        for (var ci = 0; ci < node.args.length; ci++) {
          var cv = evalExpr(node.args[ci], row, params, exRow);
          if (cv !== null && cv !== undefined) return cv;
        }
        return null;
      case 'not': return !truthy(evalExpr(node.e, row, params, exRow));
      case 'and': return truthy(evalExpr(node.l, row, params, exRow)) && truthy(evalExpr(node.r, row, params, exRow));
      case 'or': return truthy(evalExpr(node.l, row, params, exRow)) || truthy(evalExpr(node.r, row, params, exRow));
      case 'isnull': {
        var iv = evalExpr(node.e, row, params, exRow);
        return node.neg ? iv !== null && iv !== undefined : iv === null || iv === undefined;
      }
      case 'in': {
        var inv = evalExpr(node.e, row, params, exRow);
        var hit = false;
        for (var ii = 0; ii < node.list.length; ii++) {
          if (cmpVals(inv, '=', evalExpr(node.list[ii], row, params, exRow))) { hit = true; break; }
        }
        return node.neg ? !hit : hit;
      }
      case 'like': {
        var lv = evalExpr(node.e, row, params, exRow);
        var lp = evalExpr(node.pat, row, params, exRow);
        var le = node.esc ? evalExpr(node.esc, row, params, exRow) : null;
        var m2 = likeMatch(lv, lp, le);
        return node.neg ? !m2 : m2;
      }
      case 'cmp': return cmpVals(evalExpr(node.l, row, params, exRow), node.op, evalExpr(node.r, row, params, exRow));
    }
    return null;
  }
  function cmpVals(a, op, b) {
    if (a === null || a === undefined || b === null || b === undefined) {
      return op === '!=' || op === '<>' ? !(a === null || a === undefined ? b === null || b === undefined : false) : false;
    }
    var na = typeof a === 'number' ? a : (/^-?\d+(\.\d+)?$/.test(String(a)) ? parseFloat(a) : null);
    var nb = typeof b === 'number' ? b : (/^-?\d+(\.\d+)?$/.test(String(b)) ? parseFloat(b) : null);
    var x, y;
    if (na !== null && nb !== null) { x = na; y = nb; }
    else { x = String(a); y = String(b); }
    switch (op) {
      case '=': return x === y;
      case '!=': case '<>': return x !== y;
      case '<': return x < y;
      case '<=': return x <= y;
      case '>': return x > y;
      case '>=': return x >= y;
    }
    return false;
  }
  function likeMatch(value, pattern, esc) {
    if (value === null || value === undefined || pattern === null || pattern === undefined) return false;
    var e = esc || null;
    var re = '';
    var s = String(pattern);
    for (var i = 0; i < s.length; i++) {
      var ch = s.charAt(i);
      if (e && ch === e && i + 1 < s.length) { re += s.charAt(i + 1).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); i++; continue; }
      if (ch === '%') { re += '[\\s\\S]*'; continue; }
      if (ch === '_') { re += '[\\s\\S]'; continue; }
      re += ch.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
    // SQLite LIKE is ASCII-case-insensitive
    return new RegExp('^' + re + '$', 'i').test(String(value));
  }

  // split "a, b, (c, d), 'e,f'" on top-level commas
  function splitTop(s) {
    var parts = [];
    var depth = 0;
    var cur = '';
    var inStr = false;
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i);
      if (c === "'") {
        if (inStr && s.charAt(i + 1) === "'") { cur += "''"; i++; continue; }
        inStr = !inStr; cur += c; continue;
      }
      if (!inStr) {
        if (c === '(') depth++;
        if (c === ')') depth--;
        if (c === ',' && depth === 0) { parts.push(cur); cur = ''; continue; }
      }
      cur += c;
    }
    if (cur.trim().length > 0) parts.push(cur);
    return parts.map(function (p) { return p.trim(); }).filter(function (p) { return p.length > 0; });
  }

  function tableOf(state, name) {
    var t = state.tables[name];
    if (!t) throw new Error('mini-sql: no such table: ' + name);
    return t;
  }

  function createStmt(state, us) {
    if (/^CREATE\s+(UNIQUE\s+)?INDEX/i.test(us)) {
      return { rowsAffected: 0, lastInsertId: 0 }; // lab scale: full scans
    }
    if (/^CREATE\s+VIEW/i.test(us)) {
      var vm = us.match(/^CREATE\s+VIEW\s+([A-Za-z0-9_]+)/i);
      if (vm && !state.tables[vm[1]]) state.tables[vm[1]] = { cols: [], rows: [], view: true };
      return { rowsAffected: 0, lastInsertId: 0 };
    }
    var m = us.match(/^CREATE\s+TABLE\s+(IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_]+)\s*\(([\s\S]*)\)\s*;?\s*$/i);
    if (!m) throw new Error('mini-sql: bad CREATE TABLE: ' + us.slice(0, 60));
    if (state.tables[m[2]]) return { rowsAffected: 0, lastInsertId: 0 };
    var cols = [];
    var pk = null;
    splitTop(m[3]).forEach(function (d) {
      var first = d.split(/\s+/)[0].replace(/["`]/g, '');
      if (/^(PRIMARY|UNIQUE|CHECK|FOREIGN|CONSTRAINT)\b/i.test(d)) return;
      cols.push(first);
      if (/INTEGER\s+PRIMARY\s+KEY/i.test(d)) pk = first;
    });
    state.tables[m[2]] = { cols: cols, pk: pk, autoinc: /\bAUTOINCREMENT\b/i.test(us), rows: [] };
    return { rowsAffected: 0, lastInsertId: 0 };
  }

  // SQLite rowid semantics: plain INTEGER PRIMARY KEY takes max(rows)+1 (a
  // DELETE lets ids get reused); AUTOINCREMENT keeps a persistent high-water
  // mark so ids never repeat (sqlite_sequence).
  function nextRowid(state, name) {
    var table = state.tables[name];
    if (table.autoinc) {
      if (!state.seq[name]) {
        var hi = 0;
        table.rows.forEach(function (r) {
          var v = r[table.pk];
          if (typeof v === 'number' && v > hi) hi = v;
        });
        state.seq[name] = hi;
      }
      return ++state.seq[name];
    }
    var max = 0;
    table.rows.forEach(function (r) {
      var v = r[table.pk];
      if (typeof v === 'number' && v > max) max = v;
    });
    return max + 1;
  }

  function insertStmt(state, us, params) {
    // upsert: INSERT INTO t (cols) VALUES (...),(...) ON CONFLICT (keys) DO UPDATE SET c=excluded.c | DO NOTHING
    // (bookorbit single-row, statistics.db DO NOTHING, tts manifest_marks multi-row batches)
    var up = us.match(/^INSERT\s+INTO\s+([A-Za-z0-9_]+)\s*(?:\(([^)]*)\))?\s*VALUES?\s*([\s\S]+?)\s*ON\s+CONFLICT\s*\(([^)]*)\)\s*DO\s+(?:(UPDATE\s+SET\s+([\s\S]+))|(NOTHING))$/i);
    if (up) {
      var ut = tableOf(state, up[1]);
      var ucols = up[2] ? splitTop(up[2]) : ut.cols.slice();
      var uvalsAll = splitTop(up[3]);
      var ckeys = splitTop(up[4]).map(function (c) { return c.trim(); });
      var sets = up[6] ? splitTop(up[6]) : null;
      // one ?-counter shared across all row groups AND the SET clause:
      // SQLite numbers placeholders in statement order, not per-row restart
      var uq = { n: 0 };
      var affected = 0;
      var lastId = 0;
      uvalsAll.forEach(function (grp) {
        var inner = grp.replace(/^\s*\(/, '').replace(/\)\s*$/, '');
        var rawVals = splitTop(inner);
        var row = {};
        ucols.forEach(function (c, i2) {
          row[c] = rawVals[i2] !== undefined ? evalExpr(parseExprStr(rawVals[i2], uq), null, params) : null;
        });
        if (ut.pk && row[ut.pk] === null || row[ut.pk] === undefined) row[ut.pk] = nextRowid(state, up[1]);
        var existing = -1;
        for (var ri = 0; ri < ut.rows.length; ri++) {
          var hit = true;
          for (var ck = 0; ck < ckeys.length; ck++) {
            if (!cmpVals(ut.rows[ri][ckeys[ck]], '=', row[ckeys[ck]])) { hit = false; break; }
          }
          if (hit) { existing = ri; break; }
        }
        if (existing >= 0) {
          if (sets) {
            sets.forEach(function (s2) {
              var sm = s2.match(/^([A-Za-z0-9_]+)\s*=\s*([\s\S]+)$/);
              if (!sm) throw new Error('mini-sql: bad upsert SET: ' + s2);
              // bare columns read the EXISTING row; excluded.X reads the new row
              ut.rows[existing][sm[1]] = evalExpr(parseExprStr(sm[2], uq), ut.rows[existing], params, row);
            });
            affected++;
            lastId = ut.rows[existing][ut.pk || ''] || 0;
          }
        } else {
          ut.rows.push(row);
          affected++;
          lastId = row[ut.pk || ''] || 0;
        }
      });
      return { rowsAffected: affected, lastInsertId: lastId };
    }
    var m = us.match(/^INSERT\s+(?:OR\s+(IGNORE|REPLACE)\s+)?INTO\s+([A-Za-z0-9_]+)\s*(?:\(([^)]*)\))?\s*VALUES?\s*([\s\S]+)$/i);
    if (!m) {
      // statistics migration: numbers digit-product INSERT..SELECT (1..1000)
      if (/^INSERT\s+OR\s+IGNORE\s+INTO\s+numbers\b/i.test(us)) {
        var nt = tableOf(state, 'numbers');
        if (nt.rows.length === 0) {
          for (var n = 1; n <= 1000; n++) nt.rows.push({ number: n });
        }
        return { rowsAffected: nt.rows.length, lastInsertId: 0 };
      }
      throw new Error('mini-sql: unsupported INSERT: ' + us.slice(0, 60));
    }
    var mode = (m[1] || '').toUpperCase();
    var table = tableOf(state, m[2]);
    var colNames = m[3] ? splitTop(m[3]) : table.cols.slice();
    var groups = splitTop(m[4]);
    var rowsAffected = 0;
    var lastId = 0;
    var iq = { n: 0 };
    groups.forEach(function (g) {
      var inner = g.replace(/^\s*\(/, '').replace(/\)\s*$/, '');
      var rawVals = splitTop(inner);
      var row = {};
      colNames.forEach(function (c, i2) {
        row[c] = rawVals[i2] !== undefined ? evalExpr(parseExprStr(rawVals[i2], iq), null, params) : null;
      });
      if (table.pk && (row[table.pk] === null || row[table.pk] === undefined)) {
        row[table.pk] = nextRowid(state, m[2]);
      }
      var dupIdx = -1;
      if (mode === 'IGNORE' || mode === 'REPLACE') {
        for (var di = 0; di < table.rows.length; di++) {
          if (table.pk && cmpVals(table.rows[di][table.pk], '=', row[table.pk])) { dupIdx = di; break; }
        }
      }
      if (dupIdx >= 0 && mode === 'IGNORE') return;
      if (dupIdx >= 0 && mode === 'REPLACE') { table.rows[dupIdx] = row; rowsAffected++; lastId = row[table.pk]; return; }
      table.rows.push(row);
      rowsAffected++;
      lastId = table.pk ? row[table.pk] : 0;
    });
    return { rowsAffected: rowsAffected, lastInsertId: lastId };
  }

  function updateStmt(state, us, params) {
    var m = us.match(/^UPDATE\s+([A-Za-z0-9_]+)\s+SET\s+([\s\S]+)$/i);
    if (!m) throw new Error('mini-sql: bad UPDATE: ' + us.slice(0, 60));
    // split SET/WHERE at the first TOP-LEVEL WHERE only: a regex `(?:WHERE...)`
    // would cut at a WHERE inside a scalar subquery (e.g. COALESCE((SELECT ..
    // WHERE ..), 0)) and truncate the SET clause mid-expression
    var setPart = m[2];
    var wherePart = null;
    var d = 0, inS = false, cutAt = -1;
    for (var wi = 0; wi < m[2].length; wi++) {
      var wc = m[2].charAt(wi);
      if (wc === "'") {
        if (inS && m[2].charAt(wi + 1) === "'") { wi++; continue; }
        inS = !inS; continue;
      }
      if (inS) continue;
      if (wc === '(') { d++; continue; }
      if (wc === ')') { d--; continue; }
      if (d === 0 && (wi === 0 || /\s/.test(m[2].charAt(wi - 1))) &&
          /^WHERE\b/i.test(m[2].slice(wi))) { cutAt = wi; break; }
    }
    if (cutAt >= 0) {
      setPart = m[2].slice(0, cutAt);
      wherePart = m[2].slice(cutAt).replace(/^\s*WHERE\s+/i, '');
    }
    var table = tableOf(state, m[1]);
    var wq = { n: 0 };
    // parse in statement text order (SET before WHERE) so bare-'?' numbering matches SQLite
    var sets = splitTop(setPart).map(function (s2) {
      var sm = s2.match(/^([A-Za-z0-9_]+)\s*=\s*([\s\S]+)$/);
      if (!sm) throw new Error('mini-sql: bad SET: ' + s2);
      return { col: sm[1], expr: parseExprStr(sm[2], wq) };
    });
    var where = wherePart ? parseExprStr(wherePart, wq) : null;
    var n = 0;
    table.rows.forEach(function (r) {
      if (!where || truthy(evalExpr(where, r, params))) {
        sets.forEach(function (s2) { r[s2.col] = evalExpr(s2.expr, r, params); });
        n++;
      }
    });
    return { rowsAffected: n, lastInsertId: 0 };
  }

  function deleteStmt(state, us, params) {
    var m = us.match(/^DELETE\s+FROM\s+([A-Za-z0-9_]+)\s*(?:WHERE\s+([\s\S]+))?\s*$/i);
    if (!m) throw new Error('mini-sql: bad DELETE: ' + us.slice(0, 60));
    var table = tableOf(state, m[1]);
    var where = m[2] ? parseExprStr(m[2], { n: 0 }) : null;
    var kept = table.rows.filter(function (r) { return !(!where || truthy(evalExpr(where, r, params))); });
    var n = table.rows.length - kept.length;
    table.rows = kept;
    return { rowsAffected: n, lastInsertId: 0 };
  }

  function selectStmt(state, us, params) {
    var m = us.match(/^SELECT\s+([\s\S]+?)\s+FROM\s+([A-Za-z0-9_]+)\s*(?:WHERE\s+([\s\S]+?))?\s*(?:ORDER\s+BY\s+([A-Za-z0-9_]+)(?:\s+(ASC|DESC))?)?\s*(?:LIMIT\s+(\d+)(?:\s+OFFSET\s+(\d+))?)?\s*$/i);
    if (!m) throw new Error('mini-sql: unsupported SELECT: ' + us.slice(0, 60));
    var table = tableOf(state, m[2]);
    var colSpec = m[1];
    // placeholder order = text order: select list first, then WHERE
    var qctx = { n: 0 };
    var aggCols = [];
    var cols = colSpec.trim() === '*' ? table.cols.slice() : splitTop(colSpec);
    var hasAgg = false;
    if (colSpec.trim() !== '*') {
      cols = cols.map(function (c) {
        var am = c.trim().match(/^(SUM|COUNT|AVG|MIN|MAX)\s*\(\s*(\*|(?:DISTINCT\s+)?[\s\S]+?)\s*\)(?:\s+AS\s+([A-Za-z0-9_]+))?$/i);
        if (!am) return c;
        hasAgg = true;
        var distinct = /^DISTINCT\s+/i.test(am[2]);
        var exprStr = distinct ? am[2].replace(/^DISTINCT\s+/i, '') : am[2];
        aggCols.push({
          f: am[1].toUpperCase(),
          isStar: am[2].trim() === '*',
          distinct: distinct,
          expr: exprStr ? parseExprStr(exprStr, qctx) : null,
          name: am[3] || c.trim()
        });
        return null;
      });
      cols = cols.filter(function (c) { return c !== null; });
    }
    var where = m[3] ? parseExprStr(m[3], qctx) : null;
    var rows = table.rows.filter(function (r) { return !where || truthy(evalExpr(where, r, params)); });
    var isCount = /^COUNT\s*\(\s*\*\s*\)$/i.test(colSpec.trim());
    if (isCount) {
      return { rows: [{ 'count(*)': rows.length }] };
    }
    if (hasAgg) {
      // whole-result aggregates (no GROUP BY in our corpus): one output row
      var aggOut = {};
      aggCols.forEach(function (a) {
        var vals;
        if (a.isStar) {
          vals = rows.length;
        } else {
          var vs = rows.map(function (r) { return evalExpr(a.expr, r, params); })
            .filter(function (v) { return v !== null && v !== undefined; });
          if (a.distinct) {
            var seen = {};
            vs = vs.filter(function (v) {
              var key = String(v);
              if (seen[key]) return false;
              seen[key] = true;
              return true;
            });
          }
          if (a.f === 'COUNT') { vals = vs.length; }
          else if (a.f === 'SUM') {
            vals = vs.length ? vs.reduce(function (x, y) { return Number(x) + Number(y); }, 0) : null;
          } else if (a.f === 'AVG') {
            vals = vs.length ? vs.reduce(function (x, y) { return Number(x) + Number(y); }, 0) / vs.length : null;
          } else {
            vals = null;
            vs.forEach(function (v) {
              if (vals === null) { vals = v; return; }
              var lt = typeof v === 'number' && typeof vals === 'number' ? v < vals : String(v) < String(vals);
              if (a.f === 'MAX' ? !lt : lt) vals = v;
            });
          }
        }
        aggOut[a.name] = vals;
      });
      return { rows: [aggOut] };
    }
    if (m[4]) {
      var dir = (m[5] || 'ASC').toUpperCase() === 'DESC' ? -1 : 1;
      var oc = m[4];
      rows = rows.slice().sort(function (a, b) {
        var av = a[oc], bv = b[oc];
        if (av === null || av === undefined) return 1;
        if (bv === null || bv === undefined) return -1;
        if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
        return String(av) < String(bv) ? -dir : String(av) > String(bv) ? dir : 0;
      });
    }
    if (m[6] !== undefined) {
      var off = parseInt(m[7] || '0', 10);
      rows = rows.slice(off, off + parseInt(m[6], 10)); // LIMIT n [OFFSET m]: take n
    }
    var out = rows.map(function (r) {
      var o = {};
      cols.forEach(function (c) {
        var cm = c.match(/^([A-Za-z0-9_]+)(?:\s+AS\s+([A-Za-z0-9_]+))?$/i);
        var name = cm ? (cm[2] || cm[1]) : c;
        o[name] = Object.prototype.hasOwnProperty.call(r, name) ? r[name] : null;
      });
      return o;
    });
    return { rows: out };
  }

  // strip `--` line comments outside single-quoted strings (migrations carry
  // them; the frontend splits on ';' so comments arrive glued to statements)
  function stripSqlComments(sql) {
    var lines = sql.split('\n');
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var inStr = false;
      var idx = -1;
      for (var j = 0; j < line.length - 1; j++) {
        var c = line.charAt(j);
        if (c === "'") inStr = !inStr;
        if (!inStr && c === '-' && line.charAt(j + 1) === '-') { idx = j; break; }
      }
      out.push(idx >= 0 ? line.slice(0, idx) : line);
    }
    return out.join('\n');
  }

  function sqlExec(state, sql, params) {
    var us = stripSqlComments(String(sql || '')).trim();
    if (us.indexOf(';') === us.length - 1) us = us.slice(0, -1).trim();
    if (us === '') return { rowsAffected: 0, lastInsertId: 0 };
    curDbState = state;
    if (/^PRAGMA/i.test(us)) {
      var pm = us.match(/^PRAGMA\s+user_version\s*=\s*(\d+)/i);
      if (pm) { state.userVersion = parseInt(pm[1], 10); return { rowsAffected: 0, lastInsertId: 0 }; }
      if (/^PRAGMA\s+user_version/i.test(us)) return { rows: [{ user_version: state.userVersion }] };
      return { rowsAffected: 0, lastInsertId: 0 }; // wal_checkpoint etc: no-op
    }
    if (/^CREATE/i.test(us)) return createStmt(state, us);
    if (/^DROP/i.test(us)) {
      var dm = us.match(/^DROP\s+(TABLE|VIEW)\s+(IF\s+EXISTS\s+)?([A-Za-z0-9_]+)/i);
      if (dm && dm[1].toUpperCase() === 'TABLE' && state.tables[dm[3]] !== undefined) {
        delete state.tables[dm[3]];
        delete state.seq[dm[3]];
      }
      return { rowsAffected: 0, lastInsertId: 0 };
    }
    if (/^INSERT/i.test(us)) return insertStmt(state, us, params);
    if (/^UPDATE/i.test(us)) return updateStmt(state, us, params);
    if (/^DELETE/i.test(us)) return deleteStmt(state, us, params);
    if (/^SELECT/i.test(us)) return selectStmt(state, us, params);
    throw new Error('mini-sql: unsupported statement: ' + us.slice(0, 60));
  }
  window.__dbDump = function (uri) {
    var st = dbLoad(tursoName(uri));
    return JSON.stringify(st, null, 1);
  };

  function tursoName(uri) {
    var p = String(uri || '').replace(/^sqlite:/, '');
    if (p.indexOf('/lab/') === 0) p = p.slice(5); // strip the lab sandbox root
    p = p.replace(/^\/+/, '').replace(/[^A-Za-z0-9._-]+/g, '__');
    return p || 'default.db';
  }

  // plugin:turso|* over the mini-SQL engine (contract: guest-js/index.ts)
  function answerTurso(cmd, payload) {
    var args = {};
    try { args = JSON.parse(payload || '{}'); } catch (e) { /* keep going */ }
    if (cmd === 'plugin:turso|load') {
      var opts = args.options || { path: args.path || '' };
      var path = String(opts.path || '');
      dbSave(tursoName(path), dbLoad(tursoName(path))); // eager open == file create
      return Promise.resolve(JSON.stringify(path));
    }
    if (cmd === 'plugin:turso|execute') {
      var st1 = dbLoad(tursoName(args.db));
      var r1 = sqlExec(st1, args.query, args.values || []);
      dbSave(tursoName(args.db), st1);
      return Promise.resolve(JSON.stringify({ rowsAffected: r1.rowsAffected, lastInsertId: r1.lastInsertId }));
    }
    if (cmd === 'plugin:turso|load') {
      var opts = args.options || { path: args.path || '' };
      var path = String(opts.path || '');
      dbSave(tursoName(path), dbLoad(tursoName(path))); // eager open == file create
      return Promise.resolve(JSON.stringify(path));
    }
    if (cmd === 'plugin:turso|execute') {
      var st1 = dbLoad(tursoName(args.db));
      var r1 = sqlExec(st1, args.query, args.values || []);
      dbSave(tursoName(args.db), st1);
      return Promise.resolve(JSON.stringify({ rowsAffected: r1.rowsAffected, lastInsertId: r1.lastInsertId }));
    }
    if (cmd === 'plugin:turso|load') {
      var opts = args.options || { path: args.path || '' };
      var path = String(opts.path || '');
      dbSave(tursoName(path), dbLoad(tursoName(path))); // eager open == file create
      return Promise.resolve(JSON.stringify(path));
    }
    if (cmd === 'plugin:turso|execute') {
      var st1 = dbLoad(tursoName(args.db));
      var r1 = sqlExec(st1, args.query, args.values || []);
      dbSave(tursoName(args.db), st1);
      return Promise.resolve(JSON.stringify({ rowsAffected: r1.rowsAffected, lastInsertId: r1.lastInsertId }));
    }
    if (cmd === 'plugin:turso|load') {
      var opts = args.options || { path: args.path || '' };
      var path = String(opts.path || '');
      dbSave(tursoName(path), dbLoad(tursoName(path))); // eager open == file create
      return Promise.resolve(JSON.stringify(path));
    }
    if (cmd === 'plugin:turso|execute') {
      var st1 = dbLoad(tursoName(args.db));
      var r1 = sqlExec(st1, args.query, args.values || []);
      dbSave(tursoName(args.db), st1);
      return Promise.resolve(JSON.stringify({ rowsAffected: r1.rowsAffected, lastInsertId: r1.lastInsertId }));
    }
    // ---- plugin:websocket: REAL browser WebSocket passthrough (D8) ----
    // Contract (@tauri-apps/plugin-websocket dist-js): connect{url,onMessage:'__CHANNEL__:N',
    // config} → id; send{id,message:{type:'Text'|'Binary'|'Close',data}}; messages delivered
    // to the DIRECT Channel with monotonic index (Tauri v2 ordering). Real network:
    // validates the Edge TTS online path in the lab exactly as the device will.
    if (cmd === 'plugin:websocket|connect') {
      var wsUrl = String(args.url || '');
      // Edge TTS endpoint is unreachable from the lab (browser WS cannot set
      // UA/Origin + network): fail fast so TTSController's engine probe falls
      // through to native-tts instead of burning the 15s init timeout
      if (wsUrl.indexOf('msedgeservices') >= 0 || wsUrl.indexOf('edge-tts') >= 0) {
        return Promise.reject(new Error('edge endpoint unreachable in lab'));
      }
      var wsm = String(args.onMessage || '').match(/^__CHANNEL__:(\d+)$/);
      var wsCh = wsm ? parseInt(wsm[1], 10) : -1;
      var wsBrowser = new WebSocket(wsUrl);
      var wsId = ++labWsSeq;
      labWs[wsId] = { sock: wsBrowser, ch: wsCh, open: false };
      // Rust plugin semantics: connect resolves only once the socket is OPEN —
      // resolving early lets the client send during CONNECTING (InvalidStateError)
      var openResolve, openReject;
      var opened = new Promise(function (res, rej) { openResolve = res; openReject = rej; });
      wsBrowser.onopen = function () {
        if (labWs[wsId]) labWs[wsId].open = true;
        openResolve(String(wsId));
      };
      wsBrowser.onmessage = function (ev) {
        if (typeof ev.data === 'string') {
          labDeliverDirect(wsCh, { type: 'Text', data: ev.data });
        } else if (ev.data instanceof ArrayBuffer) {
          labDeliverDirect(wsCh, { type: 'Binary', data: Array.from(new Uint8Array(ev.data)) });
        } else if (ev.data && ev.data.arrayBuffer) {
          ev.data.arrayBuffer().then(function (ab) {
            labDeliverDirect(wsCh, { type: 'Binary', data: Array.from(new Uint8Array(ab)) });
          });
        }
      };
      wsBrowser.onclose = function (ev) {
        labDeliverDirect(wsCh, { type: 'Close', data: { code: ev.code, reason: ev.reason } });
        delete labWs[wsId];
      };
      wsBrowser.onerror = function () {
        openReject(new Error('ws connect failed: ' + wsUrl.slice(0, 60)));
      };
      return opened;
    }
    if (cmd === 'plugin:websocket|send') {
      var sendId = parseInt(String(args.id || '0'), 10);
      var rec = labWs[sendId];
      if (!rec || !rec.sock) return Promise.reject(new Error('websocket not found: ' + sendId));
      var msg = args.message || {};
      if (msg.type === 'Text') {
        rec.sock.send(String(msg.data));
      } else if (msg.type === 'Binary') {
        rec.sock.send(new Uint8Array(msg.data || []).buffer);
      } else if (msg.type === 'Close') {
        rec.sock.close(1000, (msg.data && msg.data.reason) || 'Disconnected by client');
        delete labWs[sendId];
      }
      return Promise.resolve('null');
    }

    // ---- plugin:http: RID protocol over real fetch (D8) ----
    // fetch{clientConfig} → rid (request fired eagerly); fetch_send{rid} →
    // {status,statusText,url,headers:[[k,v]],rid}; fetch_read_body{rid} → bytes+[1] sentinel.
    if (cmd === 'plugin:http|fetch') {
      var cfg = args.clientConfig || {};
      var rid = ++labHttpSeq;
      var url2 = String(cfg.url || '');
      var method2 = String(cfg.method || 'GET').toUpperCase();
      var fetchHeaders = {};
      (cfg.headers || []).forEach(function (pair) {
        if (pair && pair.length >= 2) fetchHeaders[String(pair[0])] = String(pair[1]);
      });
      var fetchInit = { method: method2, headers: fetchHeaders };
      if (cfg.data !== undefined && cfg.data !== null) {
        if (typeof cfg.data === 'string') fetchInit.body = cfg.data;
        else fetchInit.body = new Uint8Array(cfg.data).buffer;
      }
      // browser fetch cannot cross origins (CORS) while the device's ArkTS http
      // is unrestricted: route through the same-origin lab_server /__proxy.
      // Headers ride as a JSON array — a '\n'-joined value is an illegal fetch
      // header value once a request carries 2+ headers (D8 OPDS finding)
      var proxyHeaders = JSON.stringify(Object.keys(fetchHeaders).map(function (hk) {
        return [hk, fetchHeaders[hk]];
      }));
      labHttp[rid] = fetch('/__proxy?url=' + encodeURIComponent(url2), {
        method: method2 === 'GET' ? 'GET' : 'POST',
        headers: { 'X-Proxy-Method': method2, 'X-Proxy-Headers': proxyHeaders },
        body: fetchInit.body
      }).then(function (rsp) {
        return rsp.json().then(function (env) {
          // status 0 = proxy could not reach the target. The device's ArkTS
          // http rejects with a BusinessError here — mirror that instead of
          // feeding status 0 into the dist-js Response constructor (which
          // throws a raw TypeError into the error view)
          if (!env.status || env.status <= 0) {
            throw new Error('network unreachable: ' + url2.slice(0, 80) +
              ' (' + String(env.statusText || '').slice(0, 60) + ')');
          }
          var bodyBytes2 = [];
          try {
            var b64 = env.bodyB64 || '';
            var bin = atob(b64);
            for (var bi = 0; bi < bin.length; bi++) bodyBytes2.push(bin.charCodeAt(bi));
          } catch (e) { /* empty body */ }
          return {
            status: env.status,
            statusText: env.statusText || '',
            url: env.url || url2,
            headers: env.headers || [],
            body: bodyBytes2,
            rid: rid
          };
        });
      });
      return Promise.resolve(String(rid));
    }
    if (cmd === 'plugin:http|fetch_send') {
      var sendRid = parseInt(String(args.rid || '0'), 10);
      var pend = labHttp[sendRid];
      if (!pend) return Promise.reject(new Error('http request not found: ' + sendRid));
      return pend.then(function (info) {
        labHttpBodies[sendRid] = info.body;
        return JSON.stringify({
          status: info.status, statusText: info.statusText, url: info.url,
          headers: info.headers, rid: sendRid
        });
      });
    }
    if (cmd === 'plugin:http|fetch_read_body') {
      var bodyRid = parseInt(String(args.rid || '0'), 10);
      var bytes = labHttpBodies[bodyRid] || [];
      // Rust plugin contract (commands.rs): each read returns one chunk with
      // a 0 sentinel appended while data flows; the stream end is a BARE [1]
      // on the next call — dist-js discards data that arrives with the 1
      if (bytes.length > 0) {
        labHttpBodies[bodyRid] = [];
        return Promise.resolve(JSON.stringify(bytes.concat([0])));
      }
      delete labHttpBodies[bodyRid];
      delete labHttp[bodyRid];
      return Promise.resolve(JSON.stringify([1]));
    }
    if (cmd === 'plugin:http|fetch_cancel' || cmd === 'plugin:http|fetch_cancel_body') {
      var cancelRid = parseInt(String(args.rid || '0'), 10);
      delete labHttp[cancelRid];
      delete labHttpBodies[cancelRid];
      return Promise.resolve('null');
    }

    if (cmd === 'plugin:turso|select') {
      var st2 = dbLoad(tursoName(args.db));
      var r2 = sqlExec(st2, args.query, args.values || []);
      return Promise.resolve(JSON.stringify(r2.rows || []));
    }
    if (cmd === 'plugin:turso|batch') {
      var st3 = dbLoad(tursoName(args.db));
      var snapshot = dbClone(st3);
      try {
        (args.queries || []).forEach(function (q) { sqlExec(st3, q, []); });
      } catch (e) {
        dbSave(tursoName(args.db), snapshot); // atomic: roll the whole batch back
        return Promise.reject(e);
      }
      dbSave(tursoName(args.db), st3);
      return Promise.resolve('null');
    }
    if (cmd === 'plugin:turso|sync') {
      return Promise.resolve('null'); // local-only databases: contract no-op
    }
    if (cmd === 'plugin:turso|close') {
      return Promise.resolve('true'); // lab state IS localStorage; nothing to drain
    }
    if (cmd === 'plugin:turso|get_config') {
      return Promise.resolve('{"encrypted":false}');
    }
    return Promise.reject(new Error('unknown turso command: ' + cmd));
  }

  // ---- command answers: [ok, value-json | error-message] ----
  function answerCmd(cmd, payload, headersJson) {
    var args = {};
    try { args = JSON.parse(payload || '{}'); } catch (e) { /* keep going */ }



    // Tauri v2 fs write protocol: contents = invoke body (byte map),
    // path/options = headers (path URL-encoded, options JSON string)
    var fromHeaders = false;
    if ((cmd === 'plugin:fs|write_text_file' || cmd === 'plugin:fs|write_file')
        && args.path === undefined && headersJson && headersJson !== 'null') {
      try {
        var headers = JSON.parse(headersJson);
        if (headers.path !== undefined) {
          args.path = decodeURIComponent(headers.path);
          fromHeaders = true; // the whole body IS the contents in this protocol
        }
        if (headers.options !== undefined) {
          try { args.options = JSON.parse(headers.options); } catch (e) { /* no options */ }
        }
      } catch (e) { /* headers unreadable */ }
    }

    if (cmd === 'plugin:path|resolve_directory') {
      return [true, JSON.stringify(baseDirPath(args.directory))];
    }
    if (cmd === 'plugin:path|join') {
      var parts = (args.paths || []).map(String);
      var joined = parts.join('/').replace(/\/+/g, '/');
      return [true, JSON.stringify(joined)];
    }
    if (cmd === 'get_executable_dir') return [true, '"/lab/exec"'];
    // deep-link：lab 无深链，空数组（前端 urls ?? [] → 释放 launch gate）
    if (cmd === 'plugin:deep-link|get_current') return [true, '[]'];

    // ---- download_file（src-tauri transfer_file.rs；OPDS 书籍下载）----
    // contract: GET/POST url with headers → body to filePath, ProgressPayload
    // on the onProgress Channel, resolve with response headers record.
    // Device streams chunk-wise; lab buffers via /__proxy then emits one
    // final progress event (equivalent for multi-KB ebooks).
    if (cmd === 'download_file') {
      var dUrl = String(args.url || '');
      var dPath = resolvePath({ path: args.filePath });
      var dHeaders = args.headers || {};
      var dChM = String(args.onProgress || '').match(/^__CHANNEL__:(\d+)$/);
      var dCh = dChM ? parseInt(dChM[1], 10) : -1;
      var proxyHeaders = JSON.stringify(Object.keys(dHeaders).map(function (hk) {
        return [hk, dHeaders[hk]];
      }));
      var dHasBody = args.body !== undefined && args.body !== null;
      var dMethod = dHasBody ? 'POST' : 'GET';
      return fetch('/__proxy?url=' + encodeURIComponent(dUrl), {
        method: dMethod === 'GET' ? 'GET' : 'POST',
        headers: { 'X-Proxy-Method': dMethod, 'X-Proxy-Headers': proxyHeaders },
        body: dHasBody ? String(args.body) : undefined
      }).then(function (rsp) {
        return rsp.json().then(function (env) {
          if (!env.status || env.status <= 0) {
            throw new Error('network unreachable: ' + dUrl.slice(0, 80));
          }
          if (env.status >= 400) {
            throw new Error('http error code ' + env.status);
          }
          var b64 = env.bodyB64 || '';
          var dLen = Math.floor(b64.length * 3 / 4);
          if (dCh >= 0) {
            labDeliverDirect(dCh, { progress: dLen, total: dLen, transferSpeed: dLen });
          }
          var files = loadFiles();
          files[dPath] = { __b64: b64 };
          saveFiles(files);
          var rh = {};
          (env.headers || []).forEach(function (pair) {
            if (pair && pair.length >= 2 && rh[pair[0]] === undefined) {
              rh[pair[0]] = pair[1];
            }
          });
          return JSON.stringify(rh);
        });
      });
    }

    if (cmd === 'plugin:fs|exists') {
      var p = resolvePath(args);
      var files = loadFiles();
      var dirs = loadDirs();
      var hit = Object.prototype.hasOwnProperty.call(files, p)
        || dirs.indexOf(p) >= 0
        || Object.keys(files).some(function (k) { return k.indexOf(p + '/') === 0; });
      return [true, String(hit)];
    }
    if (cmd === 'plugin:fs|mkdir') {
      var mp = resolvePath(args);
      var dirs = loadDirs();
      if (dirs.indexOf(mp) < 0) { dirs.push(mp); saveDirs(dirs); }
      return [true, 'null'];
    }
    if (cmd === 'plugin:fs|read_text_file' || cmd === 'plugin:fs|read_file') {
      var rp = resolvePath(args);
      var files = loadFiles();
      if (!Object.prototype.hasOwnProperty.call(files, rp)) {
        return [false, 'file not found: ' + rp]; // Tauri rejects on missing file
      }
      var content = files[rp];
      // contract: plugin JS does Uint8Array.from(arr) + TextDecoder.decode ->
      // reads MUST answer with a byte array (string answers corrupt non-ASCII)
      var bytes;
      if (content && typeof content === 'object' && typeof content.__b64 === 'string') {
        // binary channel: exact bytes via base64 (epub/zip etc.)
        var bin = atob(content.__b64);
        bytes = [];
        for (var bi = 0; bi < bin.length; bi++) bytes.push(bin.charCodeAt(bi));
      } else {
        var enc = new TextEncoder();
        var eb = enc.encode(String(content));
        bytes = [];
        for (var bi2 = 0; bi2 < eb.length; bi2++) bytes.push(eb[bi2]);
      }
      return [true, JSON.stringify(bytes)];
    }
    if (cmd === 'plugin:fs|write_text_file' || cmd === 'plugin:fs|write_file') {
      var wp = resolvePath(args);
      var files = loadFiles();
      var d = decodeForStore(fromHeaders ? args : args.contents);
      files[wp] = d.b64 !== undefined ? { __b64: d.b64 } : d.text;
      saveFiles(files);
      return [true, 'null'];
    }
    if (cmd === 'plugin:fs|remove') {
      var dp = resolvePath(args);
      var files = loadFiles();
      Object.keys(files).forEach(function (k) {
        if (k === dp || k.indexOf(dp + '/') === 0) delete files[k];
      });
      saveFiles(files);
      saveDirs(loadDirs().filter(function (d) { return d !== dp && d.indexOf(dp + '/') !== 0; }));
      return [true, 'null'];
    }

    var defaults = {
      // native-bridge commands MUST carry the plugin: prefix — the bare-name
      // keys silently missed and answered null (found in D2 block C harvest)
      'plugin:native-bridge|get_system_color_scheme': '{"scheme":"light"}',
      'plugin:native-bridge|get_status_bar_height': '{"height":32}',
      'plugin:native-bridge|get_safe_area_insets': '{"top":32,"bottom":0,"left":0,"right":0}',
      'plugin:native-bridge|has_ambient_light_sensor': '{"available":false}',
      'plugin:native-bridge|get_sync_passphrase': '{"passphrase":null,"error":null}',
      'is_updater_disabled': 'true',
      'get_webview_version': '"125.0.0.0"',
      'plugin:native-bridge|is_sync_keychain_available': '{"available":true}',
      'plugin:native-bridge|get_bookshelf_widget_instances': '{"instances":[]}',
      'plugin:native-bridge|get_reading_widget_instances': '{"instances":[]}',
      'plugin:native-bridge|get_screen_brightness': '{"brightness":0.5}',
      'plugin:native-bridge|get_system_color_scheme': '{"colorScheme":"light"}',
      'plugin:native-bridge|get_sys_fonts_list': '{"fonts":{"HarmonyOS Sans":"HarmonyOS Sans","HarmonyOS Serif":"HarmonyOS Serif"}}',
      'plugin:native-bridge|has_ambient_light_sensor': '{"available":true}',
      'plugin:native-bridge|start_ambient_light_updates': '{"success":true}',
      'plugin:native-bridge|stop_ambient_light_updates': '{"success":true}',
      'plugin:native-bridge|set_sync_passphrase': '{"success":true}',
      'plugin:native-bridge|clear_sync_passphrase': '{"success":true}',
      'plugin:native-bridge|select_directory': '{"cancelled":true}',
      'plugin:native-bridge|save_image_to_gallery': '{"success":true}'
    };
    if (Object.prototype.hasOwnProperty.call(defaults, cmd)) return [true, defaults[cmd]];

    // lab file picker simulation: tests preset window.__labPickedFiles (array
    // of absolute virtual-FS paths) before clicking 导入书籍; unset -> cancel
    // plugin-listener registration is uniform (any plugin prefix): track
    // 'plugin|event' -> Channel callback id; TTS/picker/ambient push through it
    if (cmd.indexOf('|register_listener') > 0) {
      var plugin = cmd.split('|')[0].replace('plugin:', '');
      var h = args.handler;
      var hm = typeof h === 'string' ? h.match(/^__CHANNEL__:(\d+)$/) : null;
      if (hm) labChannels[plugin + '|' + String(args.event)] = parseInt(hm[1], 10);
      return [true, 'null'];
    }
    if (cmd.indexOf('|remove_listener') > 0) {
      var plugin2 = cmd.split('|')[0].replace('plugin:', '');
      if (labChannels[plugin2 + '|' + String(args.event)] !== undefined) delete labChannels[plugin2 + '|' + String(args.event)];
      return [true, 'null'];
    }
    // Tauri v2 Channel delivers ONLY index === nextIndex; any other index is
    // parked in pendingMessages forever. So every emit must carry a per-channel
    // monotonic index (keyed with the channel id: a re-registered listener is a
    // fresh Channel whose counter restarts at 0). The seq map must be PAGE
    // lifetime — a per-answerCmd local would reset on every invoke and emit
    // duplicate indexes for later utterances (D7: sentence 2's start/end were
    // dropped as duplicate index 0/1 and playback wedged after one sentence).
    function pushChannel(pluginName, eventName, message) {
      var key2 = pluginName + '|' + eventName;
      var ch = labChannels[key2];
      if (ch === undefined) return;
      var seqKey = key2 + '#' + ch;
      var idx = labChannelSeq[seqKey] || 0;
      labChannelSeq[seqKey] = idx + 1;
      try {
        window.__deliverEvent(ch, JSON.stringify({ index: idx, message: message }));
      } catch (e) { /* page gone */ }
    }

    // TTS mock aligned with device semantics (OHOS engine callbacks: start ->
    // end per utterance; no sentence boundaries) — validates the frontend's
    // highlight-advance tolerance exactly as the device will behave
    if (cmd === 'plugin:native-tts|init') return [true, '{"success":true}'];
    if (cmd === 'plugin:native-tts|check') return [true, '{"success":true}'];
    if (cmd === 'plugin:native-tts|speak') {
      var sp = args.payload || {};
      var uid = 'lab-tts-' + Date.now() + '-' + Math.floor(Math.random() * 1000);
      if (sp.preload) {
        return [true, JSON.stringify({ utteranceId: uid })];
      }
      setTimeout(function () { pushChannel('native-tts', 'tts_events', { utteranceId: uid, code: 'start', message: '', mark: null }); }, 30);
      var dwell = Math.min(12000, 400 + String(sp.text || '').length * 90);
      setTimeout(function () { pushChannel('native-tts', 'tts_events', { utteranceId: uid, code: 'end', message: '' }); }, 30 + dwell);
      return [true, JSON.stringify({ utteranceId: uid })];
    }
    if (cmd === 'plugin:native-tts|get_all_voices') {
      return [true, JSON.stringify({ voices: [
        { id: '13', name: 'OHOS zh-CN #13', lang: 'zh-CN' },
        { id: '8', name: 'OHOS en-US #8', lang: 'en-US' }
      ] })];
    }
    if (cmd === 'plugin:native-tts|set_rate' || cmd === 'plugin:native-tts|set_pitch'
        || cmd === 'plugin:native-tts|set_voice' || cmd === 'plugin:native-tts|stop'
        || cmd === 'plugin:native-tts|pause' || cmd === 'plugin:native-tts|resume'
        || cmd.indexOf('|playout_') > 0 || cmd.indexOf('media_session') > 0
        || cmd.indexOf('media_library') > 0 || cmd.indexOf('carplay') > 0) {
      if (cmd === 'plugin:native-tts|playout_position') return [true, '{"position":0}'];
      return [true, 'null'];
    }
    // D7 semantic alignment: shapes fixed against bridge.ts contracts
    if (cmd === 'plugin:native-bridge|checkPermissions'
        || cmd === 'plugin:native-bridge|request_manage_storage_permission') {
      return [true, '{"manageStorage":"granted"}'];
    }
    if (cmd === 'plugin:native-bridge|get_external_sdcard_path') return [true, '{"path":null}'];
    if (cmd === 'plugin:native-bridge|iap_is_available') return [true, '{"available":false}'];
    if (cmd === 'plugin:native-bridge|icloud_container_status') return [true, '{"available":false}'];
    if (cmd === 'plugin:native-bridge|icloud_ensure_downloaded') return [true, '{"status":"notFound"}'];
    if (cmd === 'plugin:native-bridge|query_pen_capabilities') return [true, '{"isBoox":false,"rawDrawing":false}'];




    if (cmd === 'plugin:native-bridge|show_file_picker') {
      setTimeout(function () {
        pushChannel('native-bridge', 'file-picker-result', { uris: (window.__labPickedFiles || []) });
      }, 300);
      return [true, 'null'];
    }

    if (cmd === 'plugin:fs|copy_file') {
      // importBook copies the picked epub into Books/<hash>/ — options carry
      // fromPathBaseDir / toPathBaseDir (numeric enums), not baseDir
      var cpFrom = String(args.fromPath || '');
      if (cpFrom.charAt(0) !== '/' && args.options && typeof args.options.fromPathBaseDir === 'number') {
        cpFrom = baseDirPath(args.options.fromPathBaseDir) + '/' + cpFrom;
      }
      var cpTo = String(args.toPath || '');
      if (cpTo.charAt(0) !== '/' && args.options && typeof args.options.toPathBaseDir === 'number') {
        cpTo = baseDirPath(args.options.toPathBaseDir) + '/' + cpTo;
      }
      var cpFiles = loadFiles();
      if (!Object.prototype.hasOwnProperty.call(cpFiles, cpFrom)) {
        return [false, 'file not found: ' + cpFrom];
      }
      cpFiles[cpTo] = cpFiles[cpFrom];
      saveFiles(cpFiles);
      return [true, 'null'];
    }

    // localsend semantics (service.ts): start -> LocalSendStatus, is_alive ->
    // boolean. Answering null for start sent the manager into a restart storm
    // (×107 on D4); simulate a running-but-idle service so the loop settles.
    if (cmd === 'localsend_start') {
      return [true, JSON.stringify({
        running: true,
        alias: 'Readest-Lab',
        port: 53317,
        fingerprint: 'lab:mock',
        deviceModel: 'HarmonyOS',
        localIps: ['127.0.0.1'],
        multicastError: null
      })];
    }
    if (cmd === 'localsend_is_alive') return [true, 'true'];
    if (cmd === 'localsend_stop' || cmd === 'localsend_set_discoverable') return [true, 'null'];

    if (cmd === 'plugin:dialog|open') {
      var picked = null;
      try { picked = window.__labPickedFiles || null; } catch (e) { picked = null; }
      return [true, JSON.stringify(picked)];
    }
    if (cmd === 'plugin:dialog|save') return [true, 'null'];
    if (cmd === 'plugin:dialog|ask' || cmd === 'plugin:dialog|message') {
      return [true, 'true'];
    }
    return [true, 'null'];
  }

  // ---- boot diagnostics: catch page errors/rejections (mock loads before app code) ----
  window.__errors = [];
  window.addEventListener('error', function (e) {
    window.__errors.push('error: ' + (e.message || '') + ' @' + (e.filename || '') + ':' + (e.lineno || 0));
  });
  window.addEventListener('unhandledrejection', function (e) {
    window.__errors.push('rejection: ' + String(e && e.reason ? e.reason : e));
  });
  ['error', 'warn', 'log'].forEach(function (level) {
    var orig = console[level] ? console[level].bind(console) : function () { /* no-op */ };
    console[level] = function () {
      try { window.__errors.push('console.' + level + ': ' + Array.prototype.join.call(arguments, ' ')); } catch (e) { /* keep going */ }
      orig.apply(null, arguments);
    };
  });

  // ---- full invoke census INCLUDING commands the shim answers locally ----
  window.__allInvokes = [];
  if (window.__TAURI_INTERNALS__ && window.__TAURI_INTERNALS__.invoke) {
    var origInvoke = window.__TAURI_INTERNALS__.invoke.bind(window.__TAURI_INTERNALS__);
    window.__TAURI_INTERNALS__.invoke = function (cmd, args, options) {
      try { window.__allInvokes.push(cmd); } catch (e) { /* keep going */ }
      var p = origInvoke(cmd, args, options);
      try {
        p.then(function (v) {
          if (v === null || v === undefined) {
            try { window.__errors.push('invoke-null: ' + cmd); } catch (e) { /* keep going */ }
          }
        }, function (err) {
          try { window.__errors.push('invoke-reject: ' + cmd + ' :: ' + String(err)); } catch (e) { /* keep going */ }
        });
      } catch (e) { /* keep going */ }
      return p;
    };
  }

  window.__ohosBridge = {
    invoke: function (cmd, id, payload, headersJson) {
      // truncate giant payloads (a 1MB epub write is a multi-MB JSON string —
      // keeping it verbatim starved the page, D4 finding)
      var p2 = payload;
      try {
        if (typeof payload === 'string' && payload.length > 8192) {
          p2 = payload.slice(0, 8192) + '...[' + payload.length + 'B truncated]';
        }
      } catch (e) { /* keep going */ }
      try { window.__census.push([cmd, p2, headersJson || null]); } catch (e) { /* keep going */ }
      // async path (Promise protocol): turso mini-SQL, and the D8 network
      // passthroughs (websocket/http) which answerTurso also hosts
      if (cmd.indexOf('plugin:turso|') === 0 || cmd.indexOf('plugin:websocket|') === 0
          || cmd.indexOf('plugin:http|') === 0) {
        answerTurso(cmd, payload)
          .then(function (json) { window.__shimResolve(id, true, json); })
          .catch(function (err) {
            var msg = String((err && err.message) || err);
            try { window.__errors.push('turso-reject: ' + cmd + ' :: ' + msg); } catch (e) { /* keep going */ }
            window.__shimResolve(id, false, JSON.stringify(msg));
          });
        return;
      }
      setTimeout(function () {
        try {
          var r = answerCmd(cmd, payload, headersJson);
          if (r && typeof r.then === 'function') {
            // async answer (plugin:http fetch_send awaits the real network)
            r.then(
              function (json) { window.__shimResolve(id, true, json); },
              function (err) {
                var msg = String((err && err.message) || err);
                window.__shimResolve(id, false, JSON.stringify(msg));
              }
            );
          } else {
            window.__shimResolve(id, r[0], r[1]);
          }
        } catch (e) {
          console.error('[mock] resolve failed for ' + cmd + ': ' + e);
        }
      }, 0);
    },
    notify: function (cmd, payload) {
      try { window.__census.push(['notify:' + cmd, payload]); } catch (e) { /* keep going */ }
    }
  };

  window.__dumpCensus = function () {
    var counts = {};
    window.__census.forEach(function (entry) {
      var k = entry[0];
      counts[k] = (counts[k] || 0) + 1;
    });
    return JSON.stringify(counts, null, 1);
  };

  console.log('[mock] __ohosBridge installed (fs-sim ready)');
})();
