#!/usr/bin/env python3
"""
워크스페이스 전체 dirty 프로젝트 triage.
각 프로젝트 → git status + diff stat + 최근 커밋 → Gemma가 분석 →
{뭐 만들다 만 거 / 정리 난이도 / 우선순위 / 권고 조치}.

출력: ~/.claude/cache/triage-dirty/{YYYY-MM-DD}.md
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _lib_ini_call import call_ollama  # noqa: E402

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
WORKSPACE = Path.home() / "Workspace"
OUT_DIR = Path.home() / ".claude" / "cache" / "triage-dirty"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# 미커밋 파일 수 임계치 (이 이하는 스킵)
MIN_DIRTY = 2
# 상위 N개만 Gemma 분석 (전체는 오래 걸림)
MAX_ANALYZE = int(os.environ.get("TRIAGE_TOP", "20"))


def log(msg):
    print(msg, flush=True)


def collect_dirty_projects():
    projects = []
    for d in sorted(WORKSPACE.iterdir()):
        if not d.is_dir() or not (d / ".git").exists():
            continue
        try:
            status = subprocess.run(
                ["git", "-C", str(d), "status", "--porcelain"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            if not status:
                continue
            dirty_count = len(status.splitlines())
            if dirty_count < MIN_DIRTY:
                continue

            # 추가 정보
            branch = subprocess.run(
                ["git", "-C", str(d), "branch", "--show-current"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()

            # 마지막 커밋
            last_commit = subprocess.run(
                ["git", "-C", str(d), "log", "-1", "--pretty=format:%h %s (%ar)"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()

            # diff stat (최대 30줄)
            diff_stat = subprocess.run(
                ["git", "-C", str(d), "diff", "--stat"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            diff_stat_lines = diff_stat.split("\n")[:30]

            # 파일 목록 카테고리 추정
            ext_counter = {}
            for line in status.splitlines():
                parts = line.strip().split(maxsplit=1)
                if len(parts) < 2:
                    continue
                fp = parts[1]
                ext = Path(fp).suffix or "(no-ext)"
                ext_counter[ext] = ext_counter.get(ext, 0) + 1

            projects.append({
                "name": d.name,
                "path": str(d),
                "branch": branch,
                "dirty_count": dirty_count,
                "last_commit": last_commit,
                "diff_stat": "\n".join(diff_stat_lines),
                "status_preview": "\n".join(status.splitlines()[:15]),
                "ext_counter": ext_counter,
            })
        except Exception:
            continue

    projects.sort(key=lambda x: -x["dirty_count"])
    return projects


def gemma_analyze(proj):
    prompt = f"""다음은 git 저장소의 미커밋 변경사항이다. 간결하게 분석해줘.

프로젝트: {proj['name']}
브랜치: {proj['branch']}
미커밋 파일 수: {proj['dirty_count']}
마지막 커밋: {proj['last_commit']}

파일 확장자 분포:
{json.dumps(proj['ext_counter'], ensure_ascii=False)}

미커밋 파일 (상위 15):
{proj['status_preview']}

diff stat (상위 30):
{proj['diff_stat']}

형식 (정확히 5줄, 한국어):
작업 추정: <뭘 만들다 만 것 같은지 한 줄>
정리 난이도: <쉬움 / 보통 / 어려움>
우선순위: <긴급 / 높음 / 중간 / 낮음>
권고 조치: <커밋 / 폐기 / 스태시 / 더 작업 필요 — 한 줄 이유>
예상 커밋 수: <숫자>
"""
    try:
        response = call_ollama(
            prompt,
            model="gemma4:e4b",
            num_predict=300,
            temperature=0.3,
            timeout=30,
            caller="gemma-triage-dirty",
        )
        return response.strip() if response else "[분석 실패: empty response]"
    except Exception as e:
        return f"[분석 실패: {e}]"


def parse_triage(raw):
    result = {}
    for line in raw.split("\n"):
        line = line.strip()
        for key_kr, key_en in [
            ("작업 추정:", "work"),
            ("정리 난이도:", "difficulty"),
            ("우선순위:", "priority"),
            ("권고 조치:", "action"),
            ("예상 커밋 수:", "commits"),
        ]:
            if line.startswith(key_kr):
                result[key_en] = line[len(key_kr):].strip()
                break
    return result


def priority_rank(p):
    order = {"긴급": 0, "높음": 1, "중간": 2, "낮음": 3}
    return order.get(p, 99)


def main():
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        urllib.request.urlopen(req, timeout=3).read()
    except Exception as e:
        log(f"⚠️ Ollama 접근 불가 — {e}")
        return 1

    log("=== 미커밋 프로젝트 triage ===")
    log(f"  상위 {MAX_ANALYZE}개 분석 (환경변수 TRIAGE_TOP 으로 조정)")

    log("\n1/3 dirty 프로젝트 수집 중...")
    all_dirty = collect_dirty_projects()
    log(f"  총 {len(all_dirty)}개 발견 (최소 {MIN_DIRTY}개 이상 변경)")

    to_analyze = all_dirty[:MAX_ANALYZE]
    log(f"  상위 {len(to_analyze)}개 Gemma 분석")

    log("\n2/3 Gemma 분석 중...")
    results = []
    for i, p in enumerate(to_analyze, 1):
        log(f"  [{i}/{len(to_analyze)}] {p['name']} ({p['dirty_count']}개 파일)...")
        t0 = time.time()
        raw = gemma_analyze(p)
        parsed = parse_triage(raw)
        p["triage_raw"] = raw
        p["triage"] = parsed
        p["elapsed"] = round(time.time() - t0, 1)
        results.append(p)

    log("\n3/3 리포트 생성 중...")
    date_str = datetime.now().strftime("%Y-%m-%d")
    out_file = OUT_DIR / f"{date_str}.md"

    # 우선순위 정렬
    results.sort(key=lambda x: (priority_rank(x["triage"].get("priority", "")), -x["dirty_count"]))

    parts = [
        f"# 미커밋 프로젝트 Triage — {date_str}",
        "",
        f"생성: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"총 dirty 프로젝트: {len(all_dirty)}개",
        f"분석 완료: {len(results)}개 (상위 {MAX_ANALYZE})",
        "",
        "## 우선순위별 정리 대상",
        "",
        "| 우선순위 | 프로젝트 | 파일 수 | 난이도 | 권고 | 작업 추정 |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for p in results:
        t = p["triage"]
        work = (t.get("work", "") or "").replace("|", "／")[:50]
        action = (t.get("action", "") or "").replace("|", "／")[:40]
        parts.append(
            f"| {t.get('priority', '-')} | {p['name']} | {p['dirty_count']} | {t.get('difficulty', '-')} | {action} | {work} |"
        )

    parts.extend([
        "",
        "## 상세 분석",
        "",
    ])

    for p in results:
        parts.extend([
            f"### {p['name']}",
            "",
            f"- 브랜치: `{p['branch']}`",
            f"- 미커밋 파일: {p['dirty_count']}개",
            f"- 마지막 커밋: {p['last_commit']}",
            f"- 분석 소요: {p['elapsed']}초",
            "",
            "**Gemma 분석**:",
            "",
            f"```\n{p['triage_raw']}\n```",
            "",
        ])

    # 분석 안 된 나머지 요약
    if len(all_dirty) > MAX_ANALYZE:
        parts.extend([
            "## 분석 안 된 나머지",
            "",
            f"상위 {MAX_ANALYZE}개 외 {len(all_dirty) - MAX_ANALYZE}개 프로젝트:",
            "",
        ])
        for p in all_dirty[MAX_ANALYZE:]:
            parts.append(f"- {p['name']}: {p['dirty_count']}개 파일 ({p['branch']})")

    parts.extend([
        "",
        "---",
        "",
        "_자동 생성: `~/.claude/scripts/gemma-triage-dirty.py`_",
        "_환경변수 `TRIAGE_TOP=30` 로 분석 개수 조정 가능_",
    ])

    report = "\n".join(parts)
    out_file.write_text(report, encoding="utf-8")

    log(f"\n✅ 저장: {out_file}")
    log(f"\n{'='*60}")

    # 요약만 stdout
    log(f"\n## 우선순위 Top 5")
    for p in results[:5]:
        t = p["triage"]
        log(f"  [{t.get('priority', '-')}] {p['name']} ({p['dirty_count']}개) — {t.get('action', '-')}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
