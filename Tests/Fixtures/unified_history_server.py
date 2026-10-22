"""Loopback synthetic library: real API/repositories, local media and progress semantics."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
from urllib.parse import urlparse
import json
import subprocess
import tempfile

lock = Lock()
state = {"offline": False, "position": 0, "watched": False, "mediaRequests": 0, "progressPosts": 0, "progressDeletes": 0, "deleted": False, "deleteError": False, "videoDeletes": 0}
# Long enough for deterministic pause/seek/relaunch UI work. Generated only in
# the fixture's temporary directory; no extra binary is committed to the app.
fixture_directory = tempfile.TemporaryDirectory(prefix="fold-unified-history-")
media_root = Path(fixture_directory.name)
for filename in ("parity-h264.mp4", "parity-vp9.webm"):
    subprocess.run(["ffmpeg", "-v", "error", "-stream_loop", "5", "-i", str(Path(__file__).parent / "media" / filename), "-c", "copy", str(media_root / filename)], check=True)
state["codec"] = "h264"
def selected_media():
    return media_root / ("parity-vp9.webm" if state["codec"] == "vp9" else "parity-h264.mp4")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def send(self, code, data=b"", headers=None):
        self.send_response(code)
        for key, value in (headers or {}).items(): self.send_header(key, value)
        self.send_header("Content-Length", str(len(data))); self.end_headers()
        if self.command != "HEAD":
            try: self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError): pass
    def json(self, code, data): self.send(code, json.dumps(data).encode(), {"Content-Type": "application/json"})
    def video(self):
        with lock: point, watched = state["position"], state["watched"]
        return {"youtube_id": "HISTORY0001", "title": "Unified playback fixture", "description": "Synthetic Library and Downloads playback.",
                "channel": {"channel_id": "UCHISTORY", "channel_name": "Fixture Studio"},
                "media_url": "/media/fixture." + ("webm" if state["codec"] == "vp9" else "mp4"), "media_size": selected_media().stat().st_size,
                "player": {"duration": 72, "duration_str": "1:12", "position": point, "progress": point / 72 * 100, "watched": watched},
                "streams": [{"type": "video", "codec": state["codec"], "width": 640, "height": 360}]}
    def ready(self):
        with lock: offline = state["offline"]
        if offline: self.json(503, {"detail": "Synthetic server offline"}); return False
        if self.headers.get("Authorization") != "Token HISTORY_FIXTURE_TOKEN":
            self.json(401, {"detail": "Synthetic authentication required"}); return False
        return True
    def do_HEAD(self): self.do_GET()
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/fixture-state":
            with lock: snapshot = dict(state)
            return self.json(200, snapshot)
        if not self.ready(): return
        if path in ("/media/fixture.mp4", "/media/fixture.webm"):
            with lock: state["mediaRequests"] += 1
            data = selected_media().read_bytes(); headers = {"Content-Type": "video/webm" if state["codec"] == "vp9" else "video/mp4", "Accept-Ranges": "bytes"}
            if self.headers.get("Range"):
                start, end = self.headers["Range"].removeprefix("bytes=").split("-")
                start = int(start or 0); end = min(int(end or len(data)-1), len(data)-1)
                if start >= len(data): return self.send(416, headers={"Content-Range": f"bytes */{len(data)}"})
                headers["Content-Range"] = f"bytes {start}-{end}/{len(data)}"
                return self.send(206, data[start:end+1], headers)
            return self.send(200, data, headers)
        if path == "/api/ping": return self.json(200, {"response": "pong", "user": 7})
        if path == "/api/user/account": return self.json(200, {"id": 7, "name": "Synthetic account", "is_superuser": True, "is_staff": True})
        if path == "/api/video/HISTORY0001": return self.json(404, {}) if state["deleted"] else self.json(200, self.video())
        if path == "/api/video": return self.json(200, {"data": [] if state["deleted"] else [self.video()], "paginate": {"current_page": 1, "last_page": 1, "total_hits": 0 if state["deleted"] else 1}})
        if path in ("/api/notification", "/api/video/HISTORY0001/comment", "/api/video/HISTORY0001/similar"): return self.json(200, [])
        if path == "/api/playlist": return self.json(200, {"data": []})
        return self.json(404, {"detail": "Synthetic endpoint unavailable"})
    def do_POST(self):
        path = urlparse(self.path).path.rstrip("/")
        data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))) or b"{}")
        if path == "/fixture-mode":
            with lock:
                if data.get("reset"):
                    state.update(position=0, watched=False, mediaRequests=0, progressPosts=0, progressDeletes=0, deleted=False, deleteError=False, videoDeletes=0)
                state["offline"] = bool(data.get("offline", False))
                if "deleteError" in data: state["deleteError"] = bool(data["deleteError"])
                if "codec" in data: state["codec"] = "vp9" if data["codec"] == "vp9" else "h264"
            return self.json(200, {})
        if not self.ready(): return
        if path == "/api/watched":
            with lock: state.update(watched=bool(data["is_watched"]), position=0)
            return self.json(200, {})
        if path == "/api/video/HISTORY0001/progress":
            with lock:
                state["progressPosts"] += 1
                if data["position"] > 5: state["position"] = data["position"]
                if data["position"] >= 64.8: state["watched"] = True
            return self.json(200, {})
        return self.json(404, {})
    def do_DELETE(self):
        if not self.ready(): return
        if urlparse(self.path).path.rstrip("/") == "/api/video/HISTORY0001":
            if state["deleteError"]: return self.json(500, {"detail": "Synthetic deletion failed"})
            with lock: state.update(deleted=True, videoDeletes=state["videoDeletes"]+1, position=0)
            return self.send(204)
        if urlparse(self.path).path.rstrip("/") == "/api/video/HISTORY0001/progress":
            with lock: state.update(position=0, progressDeletes=state["progressDeletes"]+1)
            return self.send(204)
        return self.json(404, {})

if __name__ == "__main__":
    print("Unified history fixture on 127.0.0.1:18086", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 18086), Handler).serve_forever()
