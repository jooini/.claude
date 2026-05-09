"""dashboard 공통 상수 + 전역 캐시 — 단일 위치에서만 정의."""
from pathlib import Path

PORT = 8765
HOST = "127.0.0.1"
TRACE_DIR = Path.home() / ".claude" / "cache" / "hook-trace"
LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"

# /usage endpoint 캐시 — 워머 스레드와 핸들러가 공유
# 모듈 import 시 한 번만 생성되어 모든 모듈에서 같은 dict 참조
_usage_cache = {}
