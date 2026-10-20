# Lab static server with no-store caching — python -m http.server sends no
# Cache-Control, so browsers heuristically cache unchanged-mtime JS and serve
# a STALE shim after we edit it (cost us one debugging round on D1).
import base64
import http.server
import json
import os
import socketserver
import urllib.error
import urllib.request
from urllib.parse import urlparse, parse_qs

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '.browserlab', 'www')
PORT = int(os.environ.get('LAB_PORT', '8931'))


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    # module imports require a JS MIME: python's mimetypes answers .mjs as
    # text/plain and the browser rejects the dynamic import outright
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        '.mjs': 'text/javascript',
        '.wasm': 'application/wasm',
    }

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    # ---- /__proxy?url=... : same-origin CORS-free passthrough for the mock's
    # plugin:http (browser fetch cannot cross origins; the device's ArkTS http
    # has no CORS). Returns a JSON envelope {status, statusText, url, headers, bodyB64}.
    def do_PROXY(self, forced_method):
        q = parse_qs(urlparse(self.path).query)
        target = (q.get('url') or [''])[0]
        if not target.startswith(('http://', 'https://')):
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'bad proxy url')
            return
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length) if length > 0 else None
        headers = {}
        raw_h = self.headers.get('X-Proxy-Headers') or ''
        if raw_h.startswith('['):
            # JSON form [[k, v], ...] — required once requests carry 2+ headers:
            # a '\n'-joined value is an illegal fetch header value in the browser
            try:
                for pair in json.loads(raw_h):
                    if isinstance(pair, (list, tuple)) and len(pair) >= 2:
                        headers[str(pair[0]).strip()] = str(pair[1]).strip()
            except Exception:  # noqa: BLE001
                pass
        else:
            for line in raw_h.split('\n'):
                if ':' in line:
                    k, v = line.split(':', 1)
                    headers[k.strip()] = v.strip()
        method = self.headers.get('X-Proxy-Method') or forced_method
        req = urllib.request.Request(target, data=body, method=method)
        for k, v in headers.items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=60) as rsp:
                env = {
                    'status': rsp.status,
                    'statusText': '',
                    'url': rsp.geturl(),
                    'headers': [[k, v] for k, v in rsp.headers.items()],
                    'bodyB64': base64.b64encode(rsp.read()).decode('ascii'),
                }
        except urllib.error.HTTPError as e:
            env = {
                'status': e.code,
                'statusText': '',
                'url': target,
                'headers': [[k, v] for k, v in (e.headers or {}).items()],
                'bodyB64': base64.b64encode(e.read()).decode('ascii'),
            }
        except Exception as e:  # noqa: BLE001
            env = {'status': 0, 'statusText': str(e), 'url': target, 'headers': [], 'bodyB64': ''}
        payload = json.dumps(env).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.startswith('/__proxy'):
            return self.do_PROXY('GET')
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith('/__proxy'):
            return self.do_PROXY('POST')
        return super().do_POST()

    def translate_path(self, path):
        # Next static export (trailingSlash=false) lays routes out FLAT:
        # /library -> library.html, its RSC payload -> library.txt. Deep-route
        # reloads must resolve to the sibling .html shell, not the root one
        # (root shell at /library renders a blank grid — D3 finding; the
        # device RawFileServer needs the same resolution, D4 item).
        p = super().translate_path(path)
        if os.path.isdir(p):
            idx = os.path.join(p, 'index.html')
            if os.path.isfile(idx):
                return idx
            sibling = p.rstrip('/\\') + '.html'
            if os.path.isfile(sibling):
                return sibling
            return os.path.join(self.directory, 'index.html')
        if not os.path.exists(p):
            if os.path.splitext(p)[1]:
                return p  # asset-like: keep 404 semantics
            sibling = p + '.html'
            if os.path.isfile(sibling):
                return sibling
            return os.path.join(self.directory, 'index.html')
        return p

    def log_message(self, fmt, *args):
        pass  # quiet


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


if __name__ == '__main__':
    os.chdir(os.path.abspath(ROOT))
    with Server(('127.0.0.1', PORT), NoCacheHandler) as httpd:
        print(f'lab serving {os.getcwd()} at http://127.0.0.1:{PORT}/ (no-store)', flush=True)
        httpd.serve_forever()
