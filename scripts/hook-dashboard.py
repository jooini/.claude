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
try:
    MCP_KNOWLEDGE_HTML = _load_template("mcp_knowledge.html")
except FileNotFoundError:
    MCP_KNOWLEDGE_HTML = "<h1>mcp_knowledge.html missing</h1>"

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


def _pending_finalizer():
    """백그라운드: 3초마다 _pending/*.jsonl 의 미finalize 발화를 turns.jsonl 로 옮긴다.
    PostToolUse hook 이 세션 중 동적으로 안 잡힐 때를 위한 안전망.
    transcript 마지막 user.promptId 를 끄집어와 매칭."""
    import re
    pending_dir = LIVE_DIR / "_pending"
    turns_file = LIVE_DIR / "turns.jsonl"
    while True:
        try:
            if pending_dir.exists():
                for pfile in pending_dir.glob("*.jsonl"):
                    try:
                        raw = pfile.read_text()
                    except Exception:
                        continue
                    if '"finalized":false' not in raw and '"finalized": false' not in raw:
                        continue
                    lines = [ln for ln in raw.splitlines() if ln.strip()]
                    parsed = []
                    for ln in lines:
                        try:
                            parsed.append(json.loads(ln))
                        except Exception:
                            parsed.append(None)
                    # 미finalize 가장 오래된 1건
                    target_idx = None
                    for i, d in enumerate(parsed):
                        if d and not d.get("finalized", False):
                            target_idx = i; break
                    if target_idx is None:
                        continue
                    target = parsed[target_idx]
                    ts_path = target.get("transcript", "")
                    if not ts_path or not Path(ts_path).exists():
                        continue
                    # transcript 에서 이미 turns.jsonl 에 없는 가장 최근 user.promptId 추출
                    existing_tids = set()
                    if turns_file.exists():
                        for tl in turns_file.read_text().splitlines():
                            m = re.search(r'"turn_id"\s*:\s*"([^"]+)"', tl)
                            if m: existing_tids.add(m.group(1))
                    new_pid = ""
                    try:
                        with open(ts_path) as f:
                            for ln in f:
                                try:
                                    td = json.loads(ln)
                                except Exception:
                                    continue
                                if td.get("type")=="user" and "toolUseResult" not in td:
                                    msg = td.get("message", {})
                                    c = msg.get("content") if isinstance(msg, dict) else None
                                    if isinstance(c, str):
                                        pid = td.get("promptId")
                                        if pid and pid not in existing_tids:
                                            new_pid = pid
                                            break  # 가장 오래된 미사용 promptId
                    except Exception:
                        continue
                    if not new_pid:
                        continue
                    # turns.jsonl 에 한 줄 추가 + 펜딩 finalized 마킹
                    turn_line = {
                        "turn_id": new_pid,
                        "session": target.get("session", ""),
                        "ts_utc": target.get("ts_utc", ""),
                        "prompt_preview": target.get("prompt_preview", ""),
                    }
                    try:
                        with open(turns_file, "a") as f:
                            f.write(json.dumps(turn_line, ensure_ascii=False) + "\n")
                    except Exception:
                        continue
                    target["finalized"] = True
                    parsed[target_idx] = target
                    out_lines = []
                    for orig_ln, d in zip(lines, parsed):
                        if d is None:
                            out_lines.append(orig_ln)
                        else:
                            out_lines.append(json.dumps(d, ensure_ascii=False))
                    tmp = pfile.with_suffix(pfile.suffix + ".tmp")
                    tmp.write_text("\n".join(out_lines) + "\n")
                    tmp.replace(pfile)
        except Exception:
            pass
        time.sleep(3)


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
        if self.path == "/mcp-knowledge":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(MCP_KNOWLEDGE_HTML.encode("utf-8"))
            return
        if self.path.startswith("/mcp-knowledge-data"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            days = int(qs.get("days", ["7"])[0])
            import subprocess
            try:
                subprocess.run(
                    ["/usr/bin/python3",
                     str(Path.home() / ".claude/scripts/mcp-knowledge-citation-analyze.py"),
                     str(days)],
                    capture_output=True, timeout=30,
                )
            except Exception:
                pass
            data_path = Path.home() / ".claude" / "cache" / f"mcp-knowledge-citation-{days}d.json"
            payload = {}
            if data_path.exists():
                try:
                    payload = json.loads(data_path.read_text())
                except Exception as e:
                    payload = {"error": str(e)}
            else:
                payload = {"error": "data file not found"}
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(json.dumps(payload, ensure_ascii=False).encode("utf-8"))
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

            # 추적 대상: md reads + agent-trace(tools) + turns(prompts)
            # 한 파일이라도 새 라인이 들어오면 SSE 이벤트 push → 클라이언트 디바운스 후 /chains 재요청.
            def _today_targets():
                today = datetime.now().strftime("%Y-%m-%d")
                return [
                    LIVE_DIR / f"{today}.jsonl",                # md reads
                    LIVE_DIR / f"agent-trace-{today}.jsonl",    # tool calls
                    LIVE_DIR / "turns.jsonl",                   # 발화 마커
                ]

            targets = _today_targets()
            offsets = {p: (p.stat().st_size if p.exists() else 0) for p in targets}
            try:
                while True:
                    cur = _today_targets()
                    # 날짜 롤오버 감지 — 경로 바뀐 파일은 offset 0 으로 리셋
                    if [str(p) for p in cur] != [str(p) for p in targets]:
                        new_off = {}
                        for p in cur:
                            new_off[p] = offsets.get(p, 0) if p in offsets else 0
                        offsets = new_off
                        targets = cur
                    any_new = False
                    for p in targets:
                        if not p.exists():
                            continue
                        size = p.stat().st_size
                        prev = offsets.get(p, 0)
                        if size > prev:
                            with p.open() as fh:
                                fh.seek(prev)
                                for line in fh:
                                    line = line.strip()
                                    if not line:
                                        continue
                                    try:
                                        json.loads(line)
                                        self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                                        self.wfile.flush()
                                        any_new = True
                                    except Exception:
                                        pass
                                offsets[p] = fh.tell()
                        elif size < prev:
                            # 파일이 회전/잘림 — offset 리셋
                            offsets[p] = 0
                    if not any_new:
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
    # 펜딩 발화 finalize 안전망 (PostToolUse hook 동적 미반영 대비)
    threading.Thread(target=_pending_finalizer, daemon=True).start()

    # SO_REUSEADDR을 bind 전에 설정 (재시작 시 TIME_WAIT 회피)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((HOST, PORT), StreamServer) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n종료")


if __name__ == "__main__":
    main()
