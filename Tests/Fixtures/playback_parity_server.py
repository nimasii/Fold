"""Synthetic playback only; exact fixture cookie, byte ranges, no owner endpoints."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from threading import Lock
import json
root = Path(__file__).parent / 'media'
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
        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with lock: state['offline']=bool(data['offline'])
        self.send(200, b'{}')
    def do_HEAD(self): self.do_GET()
    def do_GET(self):
        if self.path == '/counts':
            with lock: body=json.dumps(state).encode()
            return self.send(200, body, Content_Type='application/json')
        name=self.path.removeprefix('/')
        if name not in ('parity-h264.mp4', 'parity-vp9.webm', 'conversion-long-vp9.webm'): return self.send(404)
        with lock:
            state['mediaRequests']+=1
            offline=state['offline']
        if offline: return self.send(503)
        if self.headers.get('Cookie') != 'sessionid=fixture':
            with lock: state['unauthorized']+=1
            return self.send(401)
        data=((Path(__file__).resolve().parents[2] / 'TAClientTests/Fixtures' / name) if name == 'conversion-long-vp9.webm' else root/name).read_bytes()
        mime='video/webm' if name.endswith('webm') else 'video/mp4'
        headers={'Content_Type':mime, 'Accept_Ranges':'bytes'}
        requested=self.headers.get('Range')
        if requested:
            with lock: state['rangeRequests']+=1
            start, end=requested.removeprefix('bytes=').split('-')
            start=int(start or 0); end=min(int(end or len(data)-1),len(data)-1)
            if start >= len(data): return self.send(416, Content_Range=f'bytes */{len(data)}')
            headers['Content_Range']=f'bytes {start}-{end}/{len(data)}'
            return self.send(206, data[start:end+1], **headers)
        self.send(200, data, **headers)
if __name__ == '__main__':
    print('Playback fixture on 127.0.0.1:18083', flush=True)
    ThreadingHTTPServer(('127.0.0.1',18083),Handler).serve_forever()
