"""Loopback-only media fixtures. No owner media, credentials or archive writes."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Thread, Lock, Event
import json, struct, time

clip = (Path(__file__).resolve().parents[2] / 'TAClientTests/Fixtures/session-playback.mp4').read_bytes()
artwork = Path(__file__).resolve().parents[2] / 'PreviewApp/Fixtures'
lock = Lock()
state = {'offline': False, 'mediaRequests': 0, 'artworkRequests': 0, 'leakRequests': 0, 'deleteRequests': 0}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def send(self, code, body, mime='application/json', **headers):
        self.send_response(code)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(body)))
        for key, value in headers.items(): self.send_header(key, value)
        self.end_headers()
        try: self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError): pass
    def do_POST(self):
        if self.path != '/mode': return self.send(404, b'{}')
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        with lock: state['offline'] = bool(body.get('offline'))
        self.send(200, b'{}')
    def do_DELETE(self):
        with lock: state['deleteRequests'] += 1
        self.send(405, b'{}')
    def do_GET(self):
        if self.server.server_port == 18082:
            with lock: state['leakRequests'] += 1
            return self.send(200, b'NO REQUEST SHOULD ARRIVE HERE')
        if self.path == '/counts':
            with lock: result = json.dumps(state).encode()
            return self.send(200, result)
        with lock:
            state['artworkRequests' if self.path in ('/thumbnail.png', '/channel.png', '/redirect-artwork.png') else 'mediaRequests'] += 1
            offline = state['offline']
        if offline: return self.send(503, b'{"detail":"fixture server offline"}')
        if self.headers.get('Cookie') != 'sessionid=fixture' or self.path == '/unauthorized.mp4':
            return self.send(401, b'{"detail":"fixture authentication required"}')
        if self.path in ('/redirect.mp4', '/redirect-artwork.png'):
            return self.send(302, b'', Location='http://127.0.0.1:18082/leak')
        if self.path in ('/thumbnail.png', '/channel.png'):
            name = 'offline-thumbnail.png' if self.path == '/thumbnail.png' else 'offline-channel.png'
            return self.send(200, (artwork / name).read_bytes(), 'image/png')
        if self.path == '/slow.mp4':
            padding = bytes(1024 * 1024)
            data = clip + struct.pack('>I4s', len(padding) + 8, b'free') + padding
            self.send_response(200); self.send_header('Content-Type', 'video/mp4')
            self.send_header('Content-Length', str(len(data))); self.end_headers()
            try:
                for offset in range(0, len(data), 32768):
                    self.wfile.write(data[offset:offset+32768]); self.wfile.flush(); time.sleep(.25)
            except (BrokenPipeError, ConnectionResetError): pass
            return
        return self.send(200, clip, 'video/mp4')

if __name__ == '__main__':
    for port in (18081, 18082):
        server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
        Thread(target=server.serve_forever, daemon=True).start()
    print('Offline fixtures ready on loopback ports 18081 and 18082', flush=True)
    Event().wait()
