// DevTools Protocol Runtime.evaluate CLI（D12 真机窗口）
// 用法: node scripts/devtools_eval.mjs "<js 表达式>" [--json]
// 走 hdc fport tcp:9222 localabstract:webview_devtools_remote_<pid>
import { execSync } from 'node:child_process';

const HDC = 'E:/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe';
const expr = process.argv[2];
const asJson = process.argv.includes('--json');
if (!expr) { console.error('usage: devtools_eval.mjs "<expr>"'); process.exit(1); }

function sh(cmd) { return execSync(cmd, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }); }

// discover page target (socket name may change across app restarts)
let targets;
for (let attempt = 0; attempt < 3; attempt++) {
  try {
    targets = JSON.parse(sh(`curl -s http://127.0.0.1:9222/json`));
    break;
  } catch (e) {
    // (re)bind fport to the live socket
    const unix = sh(`"${HDC}" shell "cat /proc/net/unix"`).split('\n')
      .map(l => (l.match(/@webview_devtools_remote_(\d+)/) || [])[1])
      .filter(Boolean).pop();
    if (!unix) { console.error('no devtools socket; is app running?'); process.exit(2); }
    try { sh(`"${HDC}" fport rm tcp:9222`); } catch (e2) { /* not bound */ }
    sh(`"${HDC}" fport tcp:9222 localabstract:webview_devtools_remote_${unix}`);
  }
}
if (!targets) { console.error('devtools http unreachable'); process.exit(3); }
const page = targets.find(t => t.type === 'page');
if (!page) { console.error('no page target'); process.exit(4); }

const ws = new WebSocket(page.webSocketDebuggerUrl);
const msgId = 1;
ws.onopen = () => {
  ws.send(JSON.stringify({
    id: msgId, method: 'Runtime.evaluate',
    params: { expression: expr, returnByValue: true, awaitPromise: true, replMode: true }
  }));
};
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id === msgId) {
    const r = m.result;
    if (r.exceptionDetails) {
      console.error('EXC:', JSON.stringify(r.exceptionDetails.exception?.description
        || r.exceptionDetails.text).slice(0, 600));
    } else {
      const v = r.result?.value;
      console.log(typeof v === 'string' ? v : JSON.stringify(v, null, asJson ? 2 : 0));
    }
    ws.close(); process.exit(0);
  }
};
ws.onerror = (e) => { console.error('ws error'); process.exit(5); };
setTimeout(() => { console.error('timeout'); process.exit(6); }, 15000);
