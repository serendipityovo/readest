#!/usr/bin/env python3
"""KOReader-sync v1 compatible server (readest kosync provider protocol).

Endpoints actually used by the readest client (dist-js verified):
  GET  /users/auth                 Basic auth (username:password[md5])
  POST /users/create               {username, password}
  PUT  /syncs/progress             {document, progress, percentage, ...}
  GET  /syncs/progress/<digest>    latest record

Logs every request to kosync_server.log.
Run: python kosync_server.py [port]
"""
import json
import time
import base64
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

USERS = {'soaktest': 'abc123'}   # username -> password(userkey)
PROGRESS = {}
LOG = []


def logline(s):
    LOG.append(s)
    print(s, flush=True)
    with open('kosync_server.log', 'a', encoding='utf-8') as f:
        f.write(s + '\n')


class H(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth_user(self):
        # koreader sync v1: X-Auth-User/X-Auth-Key 头（readest 客户端默认），
        # connect() 探测 401 后可能切 Authorization: Basic (username:password)
        u = self.headers.get('X-Auth-User', '')
        k = self.headers.get('X-Auth-Key', '')
        if u and USERS.get(u) == k:
            return u
        h = self.headers.get('Authorization', '')
        if h.startswith('Basic '):
            try:
                import base64 as _b
                raw = _b.b64decode(h[6:]).decode()
                uu, _, pp = raw.partition(':')
                if USERS.get(uu) == pp:
                    return uu
            except Exception:
                pass
        return None

    def _basic_user(self):
        return self._auth_user()

    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/users/auth':
            u = self._auth_user()
            if u:
                logline(f'[{time.strftime("%H:%M:%S")}] AUTH ok user={u}')
                return self._json(200, {'username': u})
            logline(f'[{time.strftime("%H:%M:%S")}] AUTH FAIL')
            return self._json(401, {'message': 'unauthorized'})
        if path.startswith('/syncs/progress/'):
            u = self._auth_user()
            if not u:
                return self._json(401, {'message': 'unauthorized'})
            doc = path.rsplit('/', 1)[1]
            rec = PROGRESS.get(doc)
            logline(f'[{time.strftime("%H:%M:%S")}] GET user={u} doc={doc[:12]} hit={bool(rec)}')
            return self._json(200, rec or {})
        return self._json(404, {})

    def do_POST(self):
        ln = int(self.headers.get('Content-Length') or 0)
        try:
            data = json.loads(self.rfile.read(ln) or b'{}')
        except Exception:
            return self._json(400, {})
        if self.path.split('?')[0] == '/users/create':
            u, p = data.get('username', ''), data.get('password', '')
            if not u or not p:
                return self._json(400, {'message': 'missing fields'})
            USERS[u] = p
            logline(f'[{time.strftime("%H:%M:%S")}] CREATE user={u}')
            return self._json(200, {'username': u})
        return self._json(404, {})

    def do_PUT(self):
        ln = int(self.headers.get('Content-Length') or 0)
        try:
            data = json.loads(self.rfile.read(ln) or b'{}')
        except Exception:
            return self._json(400, {})
        if self.path.split('?')[0] == '/syncs/progress':
            u = self._auth_user()
            if not u:
                logline(f'[{time.strftime("%H:%M:%S")}] PUT UNAUTHORIZED')
                return self._json(401, {'message': 'unauthorized'})
            doc = data.get('document', '?')
            PROGRESS[doc] = data
            logline(f'[{time.strftime("%H:%M:%S")}] PUT ok user={u} doc={doc[:12]}'
                    f' pct={data.get("percentage")} progress={str(data.get("progress"))[:44]}')
            return self._json(200, {'document': doc})
        return self._json(404, {})

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8001
    logline(f'=== kosync v1 test server on :{port} ===')
    ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
