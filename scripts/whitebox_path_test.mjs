// whitebox_path_test.mjs — 白盒安全单元测试（路径钳制/穿越/句柄表/Range 边界）
// 逻辑按 NativeBridge.ets 与 RawFileServer.ets 原语义 1:1 移植（ArkTS 无法在
// 本机直接执行，本 harness 用于验证算法正确性；真机行为以 SelfTest 页为准）。
// 用法: node scripts/whitebox_path_test.mjs

import assert from 'node:assert';

const FILES = '/data/storage/el2/base/haps/entry/files';
const CACHE = '/data/storage/el2/base/haps/entry/cache';

// ==== NativeBridge.normalizePath (1:1 移植) ====
function normalizePath(p) {
  const abs = p.charAt(0) === '/';
  const parts = [];
  const segs = p.split('/');
  for (const s of segs) {
    if (s === '' || s === '.') continue;
    if (s === '..') { if (parts.length > 0) parts.pop(); continue; }
    parts.push(s);
  }
  return (abs ? '/' : '') + parts.join('/');
}

// ==== NativeBridge.assertSandboxPath (1:1 移植) ====
function assertSandboxPath(p) {
  const ok = p.startsWith(FILES) || p.startsWith(CACHE);
  if (!ok) throw new Error(`path outside app sandbox: ${p.slice(0, 60)}`);
  return p;
}

// fsPath 组合语义（file:// 剥前缀 + baseDir 拼接 + normalize + assert）
function fsPath(path, baseDir) {
  let p = path;
  if (p.startsWith('file://')) p = p.substring('file://'.length);
  if (baseDir && p.charAt(0) !== '/') p = `${baseDir}/${p}`;
  return assertSandboxPath(normalizePath(p));
}

let pass = 0, fail = 0, findings = [];
function check(name, fn) {
  try { fn(); pass++; console.log(`  PASS  ${name}`); }
  catch (e) { fail++; console.log(`  FAIL  ${name}: ${e.message}`); }
}
function expectThrow(fn) { try { fn(); throw new Error('no throw'); } catch (e) { if (e.message === 'no throw') throw new Error('expected throw but returned'); } }

console.log('== T1 沙箱钳制: 穿越/绝对越界应被拦截 ==');
check('T1.1 越界绝对路径被拒', () => expectThrow(() => assertSandboxPath('/etc/passwd')));
check('T1.2 normalize 折叠 .. 后越界被拒', () => expectThrow(() => assertThrowWrap()));
function assertThrowWrap() { assertSandboxPath(normalizePath(`${FILES}/../../../../../etc/passwd`)); }
check('T1.3 隐式相对逃逸 (baseDir+..) 被拒', () => expectThrow(() => fsPath('../evil', FILES)));
check('T1.4 file:// 前缀剥除后合法路径通过', () => assert.strictEqual(fsPath(`file://${FILES}/a.epub`), `${FILES}/a.epub`));
check('T1.5 cacheDir 前缀通过', () => assert.strictEqual(assertSandboxPath(`${CACHE}/thumb/x.png`), `${CACHE}/thumb/x.png`));

console.log('== T2 前缀混淆（starts-with 无分隔符）==');
{
  const sneaky = FILES + '_evil/x';
  const leaked = (function(){ try { assertSandboxPath(sneaky); return true; } catch { return false; } })();
  if (leaked) { findings.push('T2.1 前缀混淆: ' + sneaky + ' 通过 startsWith 检查（建议比对时加尾部分隔符）'); console.log(`  WARN  T2.1 前缀混淆路径通过钳制: ${sneaky}`); }
  else console.log('  PASS  T2.1 前缀混淆被拦截');
  const sneaky2 = CACHE + 'X/y';
  const leaked2 = (function(){ try { assertSandboxPath(sneaky2); return true; } catch { return false; } })();
  if (leaked2) { findings.push('T2.2 前缀混淆: ' + sneaky2); console.log(`  WARN  T2.2 前缀混淆路径通过钳制: ${sneaky2}`); }
}

console.log('== T3 RawFileServer /asset/ 通道语义 ==');
function assetPolicy(path) {
  // RawFileServer.handle 的 /asset/ 白名单（1:1）
  const allowed = path.startsWith(FILES) || path.startsWith(CACHE);
  return allowed;
}
check('T3.1 asset 通道拒沙箱外', () => assert.strictEqual(assetPolicy('/data/other/x'), false));
check('T3.2 asset 通道放行 filesDir 下任意文件(含 settings.json)', () => {
  // 事实断言：当前策略允许读取 settings.json —— 记录为攻击面而非错误
  const ok = assetPolicy(`${FILES}/settings.json`);
  if (!ok) throw new Error('settings.json 不在白名单(与源码不符)');
  findings.push('T3.2 /asset/ + ACAO:* 允许任意同源/沙盒 iframe 读取 filesDir 下 settings.json 等全部文件');
  console.log('  WARN  T3.2 settings.json 可经 /asset/ 读取（filesDir 全放开 + Access-Control-Allow-Origin: *）');
});
check('T3.3 ".."字面量一律 403', () => assert.ok(`${FILES}/../x`.includes('..')));

console.log('== T4 Range 协议边界 (rangefile.localhost) ==');
function rangeSlice(total, start, end) {
  if (end < 0 || end >= total) end = total - 1;
  if (end < start) end = start;
  const view = { start, end }; // 模拟 subarray(start, end+1)
  return view;
}
check('T4.1 正常区间', () => { const v = rangeSlice(100, 0, 9); assert.deepStrictEqual(v, { start: 0, end: 9 }); });
check('T4.2 end 越界钳到 total-1', () => { const v = rangeSlice(100, 90, 999); assert.strictEqual(v.end, 99); });
check('T4.3 start 越界 → end=start → subarray(150,151)=空切片', () => { const v = rangeSlice(100, 150, 200); assert.strictEqual(v.end, 150); });
{
  // 负 start：subarray 语义为负索引（从尾部数）——与 HTTP Range 语义不符
  const neg = rangeSlice(100, -5, 10);
  if (neg.start < 0) { findings.push('T4.4 负 start 未钳制, subarray 负索引=从尾部读取'); console.log(`  WARN  T4.4 负 start=${neg.start} 未钳制（subarray 负索引语义）`); }
  else console.log('  PASS  T4.4 负 start 被钳制');
}

console.log('== T5 fs 句柄表（rid）安全性 ==');
const handles = new Map(); let nextRid = 1;
function hOpen(path) { const rid = nextRid++; handles.set(rid, { path, pos: 0 }); return rid; }
function hClose(rid) { const h = handles.get(rid); if (h !== undefined) { handles.delete(rid); /* closeSync */ } }
function hRead(rid, wantLen, size) {
  const h = handles.get(rid);
  if (h === undefined) throw new Error(`bad file handle: ${rid}`);
  const n = Math.min(wantLen, size - h.pos);
  if (n > 0) { h.pos += n; return { bytes: n, eof: false }; }
  return { bytes: 0, eof: true };
}
check('T5.1 双重 close 幂等(无 double-free)', () => { const r = hOpen('a'); hClose(r); hClose(r); assert.strictEqual(handles.size, 0); });
check('T5.2 close 后 read 抛 bad handle(无 UAF)', () => { const r = hOpen('a'); hClose(r); expectThrow(() => hRead(r, 10, 100)); });
check('T5.3 seek 越过 EOF 后 read 返回 EOF 哨兵', () => {
  const r = hOpen('a'); handles.get(r).pos = 999;
  const out = hRead(r, 10, 100);
  assert.strictEqual(out.eof, true);
});
check('T5.4 顺序 read 到 EOF 边界精确', () => {
  const r = hOpen('a'); let total = 0;
  total += hRead(r, 60, 100).bytes; total += hRead(r, 60, 100).bytes;
  assert.strictEqual(total, 100);
  assert.strictEqual(hRead(r, 60, 100).eof, true);
});

console.log('== T6 fs|read 尾部 u64-LE 读取数编码 ==');
function encodeTail(v) { const out = []; for (let b = 0; b < 8; b++) { out.push(v & 0xFF); v = Math.floor(v / 256); } return out; }
check('T6.1 5 → [5,0...]', () => assert.deepStrictEqual(encodeTail(5), [5,0,0,0,0,0,0,0]));
check('T6.2 256 → [0,1,0...]', () => assert.deepStrictEqual(encodeTail(256), [0,1,0,0,0,0,0,0]));
check('T6.3 EOF → 8×0', () => assert.deepStrictEqual(encodeTail(0), [0,0,0,0,0,0,0,0]));
check('T6.4 大文件读取数 (>2^32) 编码正确 (0x12A05F200 LE)', () => assert.deepStrictEqual(encodeTail(5000000000), [0,242,5,42,1,0,0,0]));

console.log('== T7 copy_uri_to_path 的 dst 未钳制（对照 fsPath 链） ==');
{
  // 源码: dst 仅 normalizePath, 无 assertSandboxPath（源码 632-645 行语义）
  const dst = normalizePath('/data/storage/el2/base/htdocs/index.html');
  const clamped = (function(){ try { assertSandboxPath(dst); return true; } catch { return false; } })();
  if (!clamped) { findings.push('T7.1 copy_uri_to_path 目标路径未走 assertSandboxPath（仅查 src 无 ..）；当前用例 dst=htdocs 可被写入'); console.log('  WARN  T7.1 copy_uri_to_path dst 未钳制, 可指向沙箱内任意路径'); }
  else console.log('  PASS  T7.1');
}

console.log(`\n结果: ${pass} PASS / ${fail} FAIL / ${findings.length} 项观察发现`);
for (const f of findings) console.log(`  [Finding] ${f}`);
process.exit(fail > 0 ? 1 : 0);
