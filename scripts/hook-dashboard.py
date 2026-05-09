#!/usr/bin/env python3
"""
hook-dashboard — 브라우저로 훅 발동 실시간 시각화 (B안)

사용법:
  python3 ~/.claude/scripts/hook-dashboard.py
  # 자동으로 브라우저 열림 → http://localhost:8765

설계:
- Server-Sent Events (SSE)로 jsonl 새 라인 푸시
- 의존성 0 (표준 라이브러리만)
- 비용: 백그라운드 1개 프로세스 (CPU ~0%, 메모리 ~20MB)
"""
import http.server
import socketserver
import json
import os
import threading
import time
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict, deque

# dashboard 패키지 (분리된 모듈)
import sys as _sys
_sys.path.insert(0, str(Path(__file__).parent))
from dashboard.builders import (
    get_today_file, tail_lines,
    get_today_md_live_file, tail_md_live_lines,
    _read_jsonl, build_chains,
)

PORT = 8765
HOST = "127.0.0.1"
TRACE_DIR = Path.home() / ".claude" / "cache" / "hook-trace"
LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"

# HTML 템플릿 로더 — 외부 파일에서 읽음 (eager-load, encoding 명시)
_TEMPLATES_DIR = Path(__file__).parent / "dashboard" / "templates"
def _load_template(name):
    return (_TEMPLATES_DIR / name).read_text(encoding="utf-8")

HTML = _load_template("index.html")
GRAPH_HTML = _load_template("graph.html")
AGENT_QUALITY_HTML = _load_template("agent_quality.html")

# /usage endpoint 캐시 (60초 TTL — 풀 스캔 8~9초이므로 매 호출 회피)
_usage_cache = {}


def _warm_usage_cache():
    """백그라운드: 45초마다 usage 데이터 미리 계산해 캐시 적재.
    Claude projects 풀 스캔 8~9초 — 60초 TTL과 맞춰 항상 신선한 캐시 유지."""
    import subprocess
    while True:
        try:
            result = subprocess.run(
                ["/usr/bin/python3", os.path.expanduser("~/.claude/scripts/llm-usage.py"), "--json"],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                _usage_cache['payload'] = result.stdout
                _usage_cache['at'] = time.time()
        except Exception:
            pass
        time.sleep(45)  # 45초 — TTL 60초 안에 항상 갱신


def _rotate_old_logs():
    """매일 30일 이상 된 timing/trace 파일을 _archive로 이동 (삭제 안 함, 안전 우선)."""
    import shutil
    while True:
        try:
            now = time.time()
            cutoff = now - 30 * 86400  # 30일
            for d in [TRACE_DIR, Path.home() / ".claude" / "cache" / "hook-timing"]:
                if not d.exists():
                    continue
                archive = d / "_archive"
                archive.mkdir(exist_ok=True)
                for f in d.glob("*.tsv"):
                    if f.stat().st_mtime < cutoff and f.parent == d:
                        shutil.move(str(f), str(archive / f.name))
                for f in d.glob("*.jsonl"):
                    if f.stat().st_mtime < cutoff and f.parent == d:
                        shutil.move(str(f), str(archive / f.name))
        except Exception:
            pass
        # 매일 1회 (자정 직후 효과)
        time.sleep(86400)


class StreamServer(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args, **kwargs):
        pass  # 콘솔 노이즈 제거

    def handle_one_request(self):
        # 브라우저가 SSE 연결을 끊을 때 readline에서 ConnectionResetError 발생
        # → socketserver가 traceback 전체를 stderr에 찍음. 흡수해서 로그 깔끔하게.
        try:
            super().handle_one_request()
        except (ConnectionResetError, BrokenPipeError):
            self.close_connection = True
        except OSError as e:
            if e.errno in (54, 32):  # ECONNRESET, EPIPE
                self.close_connection = True
            else:
                raise

    def do_GET(self):
        if self.path == "/healthz":
            # 가벼운 헬스체크 — 외부 모니터링/디버깅용
            payload = {
                "ok": True,
                "ts": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
                "usage_cache_age": int(time.time() - _usage_cache.get('at', 0)) if _usage_cache.get('at') else None,
                "templates_loaded": [HTML[:20], GRAPH_HTML[:20], AGENT_QUALITY_HTML[:20]],
            }
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))
            return
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML.encode("utf-8"))
            return
        if self.path == "/graph":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(GRAPH_HTML.encode("utf-8"))
            return
        if self.path == "/agent-quality":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(AGENT_QUALITY_HTML.encode("utf-8"))
            return
        if self.path == "/agent-quality-rerun":
            import subprocess
            try:
                subprocess.run(["/usr/bin/python3", str(Path.home()/'.claude/scripts/agent-quality-analyze.py')],
                               capture_output=True, timeout=60)
                subprocess.run(["/usr/bin/python3", str(Path.home()/'.claude/scripts/agent-routing-learn.py')],
                               capture_output=True, timeout=30)
                msg = "분석 + 룰 학습 완료"
            except Exception as e:
                msg = f"오류: {e}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"msg": msg}).encode())
            return
        if self.path == "/agent-quality-sla":
            import subprocess
            try:
                r = subprocess.run(["/usr/bin/python3", str(Path.home()/'.claude/scripts/agent-quality-sla.py')],
                                   capture_output=True, text=True, timeout=30)
                msg = r.stdout
            except Exception as e:
                msg = f"오류: {e}"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(msg.encode("utf-8"))
            return
        if self.path == "/agent-quality-data":
            qfile = LIVE_DIR / "agent-quality.jsonl"
            data = []
            if qfile.exists():
                for ln in qfile.read_text().splitlines():
                    try:
                        data.append(json.loads(ln))
                    except Exception:
                        pass
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data, ensure_ascii=False).encode("utf-8"))
            return
        if self.path.startswith("/chains"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("turns", ["30"])[0])
            try:
                payload = build_chains(max_turns=n)
            except Exception as e:
                payload = {"error": str(e)}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
            return
        if self.path.startswith("/backfill-md"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("n", ["200"])[0])
            data = tail_md_live_lines(n)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return
        if self.path.startswith("/backfill"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("n", ["200"])[0])
            data = tail_lines(n)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return
        if self.path.startswith("/usage"):
            # 캐시: 60초 TTL — 첫 호출만 무겁고 이후는 즉답
            now = time.time()
            cached = _usage_cache.get('payload')
            cached_at = _usage_cache.get('at', 0)
            if cached and (now - cached_at) < 60:
                payload = cached
            else:
                import subprocess
                try:
                    result = subprocess.run(
                        ["/usr/bin/python3", os.path.expanduser("~/.claude/scripts/llm-usage.py"), "--json"],
                        capture_output=True, text=True, timeout=30
                    )
                    if result.returncode == 0:
                        payload = result.stdout
                        _usage_cache['payload'] = payload
                        _usage_cache['at'] = now
                    else:
                        payload = json.dumps({"error": result.stderr or "non-zero exit"})
                except subprocess.TimeoutExpired:
                    # 타임아웃 시 직전 캐시라도 반환
                    payload = cached or json.dumps({"error": "timeout — Claude projects 스캔 중. 잠시 후 새로고침."})
                except Exception as e:
                    payload = json.dumps({"error": str(e)})
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "max-age=60")
            self.end_headers()
            self.wfile.write(payload.encode("utf-8"))
            return
        if self.path == "/stream-md":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            f = get_today_md_live_file()
            offset = f.stat().st_size if f.exists() else 0
            try:
                while True:
                    cur_file = get_today_md_live_file()
                    if not cur_file.exists():
                        # heartbeat 후 파일 생기길 대기
                        try:
                            self.wfile.write(b": ping\n\n")
                            self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            return
                        time.sleep(1.0)
                        continue
                    if cur_file != f:
                        f = cur_file
                        offset = 0
                    size = cur_file.stat().st_size
                    if size > offset:
                        with cur_file.open() as fh:
                            fh.seek(offset)
                            for line in fh:
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    json.loads(line)
                                    self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                                    self.wfile.flush()
                                except Exception:
                                    pass
                            offset = fh.tell()
                    else:
                        try:
                            self.wfile.write(b": ping\n\n")
                            self.wfile.flush()
                        except (BrokenPipeError, ConnectionResetError):
                            return
                        time.sleep(0.5)
            except (BrokenPipeError, ConnectionResetError):
                return
            return
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            f = get_today_file()
            # 파일 끝부터 시작 — 백필은 /backfill로
            offset = f.stat().st_size if f.exists() else 0
            try:
                while True:
                    cur_file = get_today_file()
                    if not cur_file.exists():
                        time.sleep(0.5)
                        continue
                    if cur_file != f:
                        # 자정 넘어 새 파일
                        f = cur_file
                        offset = 0
                    size = cur_file.stat().st_size
                    if size > offset:
                        with cur_file.open() as fh:
                            fh.seek(offset)
                            for line in fh:
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    json.loads(line)  # 검증
                                    self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                                    self.wfile.flush()
                                except Exception:
                                    pass
                            offset = fh.tell()
                    else:
                        # heartbeat
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                        time.sleep(0.5)
            except (BrokenPipeError, ConnectionResetError):
                return
            return
        self.send_error(404)


def main():
    if not TRACE_DIR.exists():
        TRACE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"📊 Hook Dashboard: http://{HOST}:{PORT}")
    print(f"📁 데이터: {TRACE_DIR}")
    print("Ctrl+C 종료\n")

    # 브라우저 자동 열기 (옵션)
    if "--no-browser" not in os.sys.argv:
        threading.Timer(0.8, lambda: webbrowser.open(f"http://{HOST}:{PORT}")).start()

    # /usage 캐시 워머 시작 (별도 데몬 스레드)
    threading.Thread(target=_warm_usage_cache, daemon=True).start()
    # 30일 이상 된 로그 자동 회전
    threading.Thread(target=_rotate_old_logs, daemon=True).start()

    # SO_REUSEADDR을 bind 전에 설정 (재시작 시 TIME_WAIT 회피)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((HOST, PORT), StreamServer) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n종료")


if __name__ == "__main__":
    main()
