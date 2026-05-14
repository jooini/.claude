#!/usr/bin/env python3
"""
ini 마이그레이션 라이브 테스트 — 9개 스크립트의 ini/Ollama 호출 동작 검증.

LAN 진입 후 1번 실행하면:
1. Ollama 도달 확인
2. _lib_ini_call 헬퍼 직접 호출 테스트 (call_ollama / call_ollama_messages / force_format)
3. 마이그레이션된 7개 Python 스크립트 import + LLM 호출 함수 정의 확인
4. gemma-logger.sh 호출 1회 (인터페이스 호환성)
5. JSONL 로그에서 transport 비율 측정
6. 최근 호출 응답 시간 비교 (ini vs urllib_fallback)

사용:
    python3 ini-migration-livetest.py            # 전체 검증
    python3 ini-migration-livetest.py --quick    # health + JSONL만 (호출 안 함)
    python3 ini-migration-livetest.py --report   # 결과를 옵시디언에 저장
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPTS_DIR))

from _lib_ini_call import call_ollama, call_ollama_messages, is_ollama_reachable, INI_BIN, OLLAMA, LOG_FILE  # noqa: E402

VAULT = Path.home() / "Workspace" / "weaversbrain" / "weaversbrain"
REPORT_DIR = VAULT / "Reports" / "2026-05"

# 마이그레이션된 7개 Python 스크립트
MIGRATED_PY_SCRIPTS = [
    "gemma-puzzle.py",
    "gemma-knowledge-retry-v2.py",
    "gemma-triage-dirty.py",
    "gemma-knowledge-index.py",
    "gemma-kb-build.py",
    "gemma-health-report.py",
    "gemma-weekly-learning.py",
]

# 마이그레이션된 shell wrapper
MIGRATED_SH_SCRIPTS = [
    "gemma-logger.sh",
]


def ok(msg: str) -> str:
    return f"✅ {msg}"


def fail(msg: str) -> str:
    return f"❌ {msg}"


def warn(msg: str) -> str:
    return f"⚠️  {msg}"


def check_environment() -> dict:
    """1. 환경 검증."""
    result = {"ini_binary": False, "ollama_reachable": False, "lib_imports": False}
    print("\n=== 1. 환경 검증 ===")

    if INI_BIN.exists() and INI_BIN.stat().st_mode & 0o111:
        print(ok(f"ini binary: {INI_BIN} (executable)"))
        result["ini_binary"] = True
    else:
        print(fail(f"ini binary missing or not executable: {INI_BIN}"))

    if is_ollama_reachable(timeout=3):
        print(ok(f"Ollama reachable: {OLLAMA}"))
        result["ollama_reachable"] = True
    else:
        print(fail(f"Ollama unreachable: {OLLAMA} (LAN 진입 필요)"))

    try:
        from _lib_ini_call import call_ollama as _co  # noqa: F401
        from _lib_ini_call import call_ollama_messages as _com  # noqa: F401
        print(ok("_lib_ini_call helper import OK"))
        result["lib_imports"] = True
    except ImportError as e:
        print(fail(f"helper import failed: {e}"))

    return result


def test_helper_calls() -> dict:
    """2. 헬퍼 직접 호출 (3 패턴)."""
    result = {"call_ollama": False, "call_ollama_messages": False, "force_format_json": False}
    print("\n=== 2. 헬퍼 호출 테스트 ===")

    # Pattern A: 단일 prompt
    print("  [A] call_ollama(prompt='안녕') ...")
    t = time.time()
    resp = call_ollama("안녕. 한 단어로 답해.", model="qwen3.5:9b", num_predict=20, timeout=30, caller="livetest-A")
    elapsed = (time.time() - t) * 1000
    if resp:
        print(f"      {ok(f'response={resp[:30]!r} ({elapsed:.0f}ms)')}")
        result["call_ollama"] = True
    else:
        print(f"      {fail('empty response')}")

    # Pattern B: chat messages
    print("  [B] call_ollama_messages(system+user) ...")
    t = time.time()
    resp = call_ollama_messages(
        [
            {"role": "system", "content": "한국어로 한 단어만 답한다."},
            {"role": "user", "content": "1 더하기 1은?"},
        ],
        model="qwen3.5:9b",
        num_predict=20,
        timeout=30,
        caller="livetest-B",
    )
    elapsed = (time.time() - t) * 1000
    if resp:
        print(f"      {ok(f'response={resp[:30]!r} ({elapsed:.0f}ms)')}")
        result["call_ollama_messages"] = True
    else:
        print(f"      {fail('empty response')}")

    # Pattern C: force_format=json (urllib 강제)
    print("  [C] call_ollama_messages(force_format='json') ...")
    t = time.time()
    resp = call_ollama_messages(
        [
            {"role": "system", "content": "JSON만 출력. 형식: {\"answer\": <number>}"},
            {"role": "user", "content": "1 더하기 1은?"},
        ],
        model="qwen3.5:9b",
        num_predict=30,
        timeout=30,
        caller="livetest-C",
        force_format="json",
    )
    elapsed = (time.time() - t) * 1000
    if resp:
        try:
            parsed = json.loads(resp)
            print(f"      {ok(f'JSON parsed: {parsed} ({elapsed:.0f}ms)')}")
            result["force_format_json"] = True
        except json.JSONDecodeError:
            print(f"      {warn(f'response is not valid JSON: {resp[:50]!r}')}")
    else:
        print(f"      {fail('empty response')}")

    return result


def test_migrated_imports() -> dict:
    """3. 마이그레이션된 7개 Python 스크립트 import 검증."""
    print("\n=== 3. 마이그레이션 스크립트 import 검증 ===")
    result = {}
    for script in MIGRATED_PY_SCRIPTS:
        path = SCRIPTS_DIR / script
        if not path.exists():
            print(fail(f"{script}: file missing"))
            result[script] = False
            continue
        # Compile check (no execution)
        try:
            subprocess.run(
                [sys.executable, "-m", "py_compile", str(path)],
                check=True,
                capture_output=True,
                timeout=10,
            )
            # Helper usage check (직접 import 또는 gemma-logger.sh subprocess 호출)
            content = path.read_text(encoding="utf-8")
            uses_helper = ("_lib_ini_call" in content) or ("gemma-logger.sh" in content)
            has_direct = "/api/chat" in content and "urllib.request.urlopen" in content
            # health check만 허용
            llm_direct = sum(1 for line in content.split("\n")
                            if "urllib.request.urlopen" in line and "/api/chat" in line)
            if uses_helper and llm_direct == 0:
                print(ok(f"{script}: helper used, no direct LLM call"))
                result[script] = True
            elif uses_helper and llm_direct > 0:
                print(warn(f"{script}: helper used but {llm_direct} direct LLM calls remain"))
                result[script] = False
            else:
                print(fail(f"{script}: helper NOT used"))
                result[script] = False
        except subprocess.CalledProcessError as e:
            print(fail(f"{script}: syntax error: {e.stderr.decode()[:100]}"))
            result[script] = False
        except Exception as e:
            print(fail(f"{script}: {e}"))
            result[script] = False
    return result


def test_logger_sh() -> dict:
    """4. gemma-logger.sh 호출 (인터페이스 호환성)."""
    print("\n=== 4. gemma-logger.sh 호출 테스트 ===")
    result = {"logger_sh": False}
    logger = SCRIPTS_DIR / "gemma-logger.sh"
    if not logger.exists():
        print(fail(f"missing: {logger}"))
        return result

    t = time.time()
    proc = subprocess.run(
        [str(logger), "livetest-logger", "qwen3.5:9b", "한 단어로 답해. 안녕.", "20", "0.3"],
        capture_output=True,
        text=True,
        timeout=60,
    )
    elapsed = (time.time() - t) * 1000

    if proc.returncode == 0 and proc.stdout.strip():
        print(ok(f"gemma-logger.sh: {proc.stdout.strip()[:30]!r} ({elapsed:.0f}ms)"))
        result["logger_sh"] = True
    else:
        print(fail(f"gemma-logger.sh exit {proc.returncode}: stdout={proc.stdout[:80]!r} stderr={proc.stderr[:80]!r}"))

    return result


def analyze_jsonl_log() -> dict:
    """5. JSONL 로그 transport 비율 + 응답 시간 분석."""
    print("\n=== 5. JSONL 로그 분석 (최근 100건) ===")
    result = {"total": 0, "by_transport": {}, "avg_ms_by_transport": {}, "error_rate": 0.0}

    if not LOG_FILE.exists():
        print(warn(f"log file not found: {LOG_FILE}"))
        return result

    records = []
    with LOG_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    records = records[-100:]
    result["total"] = len(records)

    by_transport = defaultdict(list)
    errors = 0
    for r in records:
        t = r.get("transport", "unknown")
        by_transport[t].append(r.get("duration_ms", 0))
        if r.get("status") == "error":
            errors += 1

    print(f"  총 {len(records)}건 기록")
    for t, durs in sorted(by_transport.items(), key=lambda kv: -len(kv[1])):
        avg = sum(durs) / len(durs) if durs else 0
        pct = len(durs) / len(records) * 100 if records else 0
        print(f"  - {t}: {len(durs)}건 ({pct:.0f}%), 평균 {avg:.0f}ms")
        result["by_transport"][t] = len(durs)
        result["avg_ms_by_transport"][t] = round(avg, 1)

    result["error_rate"] = errors / len(records) if records else 0.0
    print(f"  에러율: {result['error_rate']*100:.1f}%")

    # ini vs urllib_fallback 비교
    if "ini" in by_transport and "urllib_fallback" in by_transport:
        ini_avg = sum(by_transport["ini"]) / len(by_transport["ini"])
        url_avg = sum(by_transport["urllib_fallback"]) / len(by_transport["urllib_fallback"])
        delta = url_avg - ini_avg
        print(f"  ini vs urllib_fallback 평균 차이: {delta:+.0f}ms ({'ini 빠름' if delta > 0 else 'urllib 빠름'})")

    return result


def render_report(env: dict, helper: dict, scripts: dict, logger: dict, log: dict) -> str:
    """결과를 마크다운 보고서로."""
    now = datetime.now()
    ts = now.strftime("%Y-%m-%d-%H%M")
    lines = [
        "---",
        f"date: {now.date()}",
        f"time: \"{now.strftime('%H:%M')}\"",
        "type: livetest-report",
        "scope: ini-migration",
        "generated_by: ini-migration-livetest.py",
        "---",
        "",
        f"# ini 마이그레이션 라이브 테스트 — {ts}",
        "",
        "## 1. 환경",
        f"- ini binary: {'✅' if env['ini_binary'] else '❌'}",
        f"- Ollama reachable: {'✅' if env['ollama_reachable'] else '❌'}",
        f"- helper imports: {'✅' if env['lib_imports'] else '❌'}",
        "",
        "## 2. 헬퍼 호출 (3 패턴)",
        f"- call_ollama (단일 prompt): {'✅' if helper['call_ollama'] else '❌'}",
        f"- call_ollama_messages (chat): {'✅' if helper['call_ollama_messages'] else '❌'}",
        f"- force_format='json' (urllib 강제): {'✅' if helper['force_format_json'] else '❌'}",
        "",
        "## 3. 마이그레이션 스크립트 검증",
    ]
    for script, ok_status in scripts.items():
        lines.append(f"- {script}: {'✅' if ok_status else '❌'}")
    lines.extend([
        "",
        "## 4. gemma-logger.sh",
        f"- 호출 성공: {'✅' if logger['logger_sh'] else '❌'}",
        "",
        "## 5. JSONL 로그 (최근 100건)",
        f"- 총 호출: {log['total']}",
        f"- 에러율: {log['error_rate']*100:.1f}%",
        "",
        "### Transport 분포",
    ])
    for t, count in sorted(log.get("by_transport", {}).items(), key=lambda kv: -kv[1]):
        avg = log["avg_ms_by_transport"].get(t, 0)
        lines.append(f"- {t}: {count}건 (평균 {avg}ms)")

    lines.extend([
        "",
        "## 종합 판정",
    ])
    all_ok = (
        all(env.values())
        and all(helper.values())
        and all(scripts.values())
        and logger["logger_sh"]
    )
    if all_ok:
        lines.append("✅ **PASS** — 마이그레이션 완전 정상")
    else:
        failed = []
        for k, v in {**env, **helper, **scripts, **logger}.items():
            if not v:
                failed.append(k)
        lines.append(f"⚠️  **PARTIAL** — 실패: {', '.join(failed)}")

    lines.extend([
        "",
        "## 다음 액션",
        "- LAN 외부에서 실행한 경우: LAN 진입 후 재실행",
        "- transport 비율에서 ini < 50% 이면 ini binary 또는 OLLAMA_HOST 점검",
        "- 에러율 > 10% 이면 jsonl 최근 에러 직접 확인:",
        f"  `tail -100 {LOG_FILE} | jq -c 'select(.status==\"error\")'`",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="ini migration livetest")
    parser.add_argument("--quick", action="store_true", help="env + JSONL만 (호출 스킵)")
    parser.add_argument("--report", action="store_true", help="결과를 옵시디언에 저장")
    args = parser.parse_args()

    env = check_environment()
    if not env["ollama_reachable"]:
        print("\n" + warn("Ollama unreachable — 호출 테스트 스킵 (LAN 진입 후 재실행)"))
        helper = {"call_ollama": False, "call_ollama_messages": False, "force_format_json": False}
        logger = {"logger_sh": False}
    elif args.quick:
        print("\n" + warn("--quick — 호출 테스트 스킵"))
        helper = {"call_ollama": False, "call_ollama_messages": False, "force_format_json": False}
        logger = {"logger_sh": False}
    else:
        helper = test_helper_calls()
        logger = test_logger_sh()

    scripts = test_migrated_imports()
    log = analyze_jsonl_log()

    report = render_report(env, helper, scripts, logger, log)
    print("\n" + "=" * 60)
    print(report)

    if args.report:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        ts = datetime.now().strftime("%Y-%m-%d-%H%M")
        out = REPORT_DIR / f"{ts}-ini-migration-livetest.md"
        out.write_text(report, encoding="utf-8")
        print(f"\n[livetest] 보고서 저장: {out}", file=sys.stderr)
        print(f"obsidian://open?vault=weaversbrain&file=Reports%2F2026-05%2F{ts}-ini-migration-livetest", file=sys.stderr)

    # exit code: 0 if all critical pass
    critical_pass = env["lib_imports"] and all(scripts.values())
    return 0 if critical_pass else 1


if __name__ == "__main__":
    sys.exit(main())
