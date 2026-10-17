"""Loopback-only UI fixtures: credited stills and generated range-capable media.
No owner server, credentials, recommendation service, or production write exists.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from urllib.parse import urlsplit
import json
import re

root = Path(__file__).parent
lock = Lock()
state = {'offline': False, 'mediaRequests': 0, 'rangeRequests': 0, 'unauthorized': 0}
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def send(self, code, data=b'', **headers):
        self.send_response(code)
        self.send_header('Content-Length', str(len(data)))
        for k, v in headers.items(): self.send_header(k.replace('_', '-'), v)
        self.end_headers()
        if self.command != 'HEAD':
            try: self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError): pass
    def do_POST(self):
        if self.path != '/mode': return self.send(405)
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with lock: state['offline'] = bool(data['offline'])
        self.send(200, b'{}', Content_Type='application/json')
    def do_HEAD(self): self.do_GET()
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/counts':
            with lock: body = json.dumps(state).encode()
            return self.send(200, body, Content_Type='application/json')
        art = re.fullmatch(r'/art/(earthrise|orbit|moon|apollo)(?:-[0-9]+)?\.jpg', path)
        if path != '/media.mp4' and not art: return self.send(404)
        with lock:
            offline = state['offline']
            if path == '/media.mp4': state['mediaRequests'] += 1
        if offline: return self.send(503)
        if self.headers.get('Authorization') != 'Token STREAMING_FIXTURE_TOKEN':
            with lock: state['unauthorized'] += 1
            return self.send(401)
        file = root / 'streaming-art' / (art.group(1) + '.jpg') if art else root / 'media/parity-h264.mp4'
        data = file.read_bytes()
        headers = {'Content_Type': 'image/jpeg' if art else 'video/mp4', 'Accept_Ranges': 'bytes'}
        requested = self.headers.get('Range')
        if requested:
            try:
                if not requested.startswith('bytes=') or ',' in requested: raise ValueError()
                first, last = requested[6:].split('-')
                start = int(first) if first else max(0, len(data) - int(last))
                end = min(int(last), len(data)-1) if first and last else len(data)-1
                if start < 0 or start >= len(data) or end < start: raise ValueError()
            except ValueError: return self.send(416, Content_Range=f'bytes */{len(data)}')
            with lock: state['rangeRequests'] += 1
            headers['Content_Range'] = f'bytes {start}-{end}/{len(data)}'
            return self.send(206, data[start:end+1], **headers)
        self.send(200, data, **headers)
if __name__ == '__main__':
    print('Streaming design fixtures: 127.0.0.1:18084 only', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18084), Handler).serve_forever()
