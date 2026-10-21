"""Loopback-only Queue/session regression server. Synthetic cookies; no real data."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Lock
from urllib.parse import urlparse, parse_qs
import json
import time

state = {"mode": "forbidden", "requests": {}, "authorized_pings": 0, "artwork_denials": 0}
lock = Lock()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log headers/cookies or request bodies.

    def send(self, code, data=b"", headers=None):
        self.send_response(code)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass  # Expected when the UI cancels an interrupted Queue entry.

    def json(self, code, value):
        self.send(code, json.dumps(value).encode(), {"Content-Type": "application/json"})

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")
        if path == "/fixture-state":
            with lock:
                snapshot = dict(state)
            return self.json(200, snapshot)
        if path == "/fixture-login":
            self.send_response(302)
            self.send_header("Set-Cookie", "sessionid=queue-synthetic; Path=/; HttpOnly")
            self.send_header("Set-Cookie", "csrftoken=queue-synthetic; Path=/")
            self.send_header("Location", "/")
            self.end_headers()
            return
        cookie = self.headers.get("Cookie", "")
        signed_in = "sessionid=queue-synthetic" in cookie
        if path.startswith("/api/") or path.startswith("/cache/"):
            with lock:
                mode = state["mode"]
                key = "GET " + path
                state["requests"][key] = state["requests"].get(key, 0) + 1
            if not signed_in or mode == "expired":
                return self.json(403, {"detail": "Authentication credentials were not provided."})
            if path == "/api/ping":
                with lock:
                    state["authorized_pings"] += 1
                return self.json(200, {"response": "pong", "user": 7, "version": "queue-auth-fixture"})
            if path == "/api/user/account":
                return self.json(200, {"id": 7, "name": "Synthetic Queue account", "is_superuser": False, "is_staff": False})
            if path == "/api/download":
                if mode == "forbidden":
                    return self.json(403, {"detail": "You do not have permission to perform this action."})
                if mode == "unauthorized":
                    return self.json(401, {"detail": "Invalid token."})
                if mode == "maintenance":
                    return self.send(503, b"<html>Fixture maintenance</html>", {"Content-Type": "text/html"})
                if mode == "slow":
                    time.sleep(2)
                    return self.send(503, b"<html>Fixture maintenance</html>", {"Content-Type": "text/html"})
                status = parse_qs(parsed.query).get("filter", ["pending"])[0]
                return self.json(200, {"data": [{"youtube_id": "QUEUEFIX001", "title": "Synthetic Queue item", "channel_name": "Fixture channel", "duration": "0:12", "published": "2026-10-20", "status": status, "vid_thumb_url": "/cache/download/QUEUEFIX001.jpg"}], "paginate": {"current_page": 1, "last_page": 1, "total_hits": 1}})
            if path == "/api/notification":
                return self.json(200, [])
            if path.startswith("/cache/"):
                with lock:
                    state["artwork_denials"] += 1
                return self.json(403, {"detail": "Forbidden artwork fixture"})
            if path.startswith("/api/video"):
                return self.json(200, {"data": [], "paginate": {"current_page": 1, "last_page": 1, "total_hits": 0}})
            return self.json(404, {"detail": "Not found"})
        message = "Signed in to the Queue fixture server. Tap Finish above." if signed_in else '<a href="/fixture-login">Sign in to Queue fixture</a>'
        html = '<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{font:18px system-ui;padding:28px}a{display:block;padding:20px;background:#1365cc;color:white}</style><h1>LOCAL QUEUE TEST FIXTURE</h1><p>' + message + '</p>'
        self.send(200, html.encode(), {"Content-Type": "text/html"})

    def do_POST(self):
        if self.path == "/fixture-mode":
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
            with lock:
                state["mode"] = data["mode"]
            return self.json(200, {"mode": data["mode"]})
        return self.json(403, {"detail": "Synthetic action denied; nothing was changed."})

if __name__ == "__main__":
    print("Queue auth fixture listening on 127.0.0.1:18085", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 18085), Handler).serve_forever()
