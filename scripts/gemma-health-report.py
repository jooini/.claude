#!/usr/bin/env python3
"""
일일 워크플로우 헬스 리포트 생성.
- 입력: 오늘 날짜 (기본) 또는 지정 날짜
- 수집: 세션 jsonl, git 커밋/미커밋/푸시, 프로젝트 전환, 도구 사용량
- 분석: Gemma가 팩폭 평가 + 내일 우선순위 추천
- 출력: ~/.claude/cache/health-report/{YYYY-MM-DD}.md
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _lib_ini_call import call_ollama  # noqa: E402

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
OUT_DIR = Path.home() / ".claude" / "cache" / "health-report"
OUT_DIR.mkdir(parents=True, exist_ok=True)

PROJECTS_ROOT = Path.home() / ".claude" / "projects"
WORKSPACE = Path.home() / "Workspace"


def log(msg):
    print(msg, flush=True)


def get_target_date():
    if len(sys.argv) > 1:
        return sys.argv[1]
    return datetime.now().strftime("%Y-%m-%d")


def ts_in_range(ts, date_str):
    try:
        if isinstance(ts, str):
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        else:
            dt = datetime.fromtimestamp(ts)
        return dt.strftime("%Y-%m-%d") == date_str
    except Exception:
        return False


def _parse_ts(ts):
    """ISO 문자열 또는 epoch → datetime. 실패 시 None."""
    if not ts:
        return None
    try:
        if isinstance(ts, str):
            return datetime.fromisoformat(ts.replace("Z", "+00:00"))
        return datetime.fromtimestamp(ts)
    except Exception:
        return None


def _extract_tool_uses(rec):
    """assistant 메시지 content 배열에서 tool_use 추출."""
    msg = rec.get("message", {})
    content = msg.get("content", [])
    if not isinstance(content, list):
        return []
    return [c for c in content if isinstance(c, dict) and c.get("type") == "tool_use"]


def analyze_sessions(date_str):
    """당일 세션 jsonl 스캔 — record 내부 timestamp 기준."""
    sessions_map = {}  # id → info
    total_user_msgs = 0
    total_tool_calls = 0
    tool_counter = defaultdict(int)
    projects_touched = set()
    first_activity = None
    last_activity = None
    edited_files = set()
    bash_commands = []

    # mtime 기준 범위 넓게 잡아 놓치지 않게 (date ± 1일)
    try:
        day_dt = datetime.strptime(date_str, "%Y-%m-%d")
    except Exception:
        return {}
    prev_day = (day_dt - timedelta(days=1)).strftime("%Y-%m-%d")
    next_day = (day_dt + timedelta(days=1)).strftime("%Y-%m-%d")

    for project_dir in PROJECTS_ROOT.iterdir():
        if not project_dir.is_dir():
            continue
        for jsonl in project_dir.glob("*.jsonl"):
            try:
                mtime = jsonl.stat().st_mtime
                mtime_day = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")
                # ±1일 여유
                if mtime_day not in (prev_day, date_str, next_day):
                    continue
            except Exception:
                continue

            session_id = jsonl.stem
            proj_name = project_dir.name.replace("-Users-leonard", "").replace("-", "/").strip("/") or "(root)"

            try:
                with jsonl.open(encoding="utf-8", errors="replace") as f:
                    for line in f:
                        try:
                            rec = json.loads(line)
                        except Exception:
                            continue

                        rec_ts = rec.get("timestamp") or rec.get("time")
                        dt = _parse_ts(rec_ts)
                        if dt is None:
                            continue
                        # 로컬 시간 기준 당일만
                        dt_local = dt.astimezone().replace(tzinfo=None) if dt.tzinfo else dt
                        if dt_local.strftime("%Y-%m-%d") != date_str:
                            continue

                        # 세션 정보 lazy 생성
                        if session_id not in sessions_map:
                            sessions_map[session_id] = {
                                "id": session_id,
                                "project": proj_name,
                                "user_msgs": 0,
                                "tools": 0,
                                "start": dt_local,
                                "end": dt_local,
                            }
                        info = sessions_map[session_id]

                        # 활동 시간 갱신
                        if first_activity is None or dt_local < first_activity:
                            first_activity = dt_local
                        if last_activity is None or dt_local > last_activity:
                            last_activity = dt_local
                        if dt_local < info["start"]:
                            info["start"] = dt_local
                        if dt_local > info["end"]:
                            info["end"] = dt_local

                        mtype = rec.get("type")
                        if mtype == "user":
                            info["user_msgs"] += 1
                            total_user_msgs += 1
                        elif mtype == "assistant":
                            # assistant 메시지 내 tool_use 배열 추출
                            for tu in _extract_tool_uses(rec):
                                tool_name = tu.get("name", "unknown")
                                tool_counter[tool_name] += 1
                                total_tool_calls += 1
                                info["tools"] += 1
                                inp = tu.get("input", {}) or {}
                                if tool_name in ("Edit", "Write", "NotebookEdit"):
                                    fp = inp.get("file_path", "")
                                    if fp:
                                        edited_files.add(fp)
                                elif tool_name == "Bash":
                                    cmd = (inp.get("command", "") or "")[:100]
                                    if cmd:
                                        bash_commands.append(cmd)
            except Exception:
                continue

            projects_touched.add(project_dir.name)

    sessions = list(sessions_map.values())

    return {
        "sessions": sessions,
        "total_user_msgs": total_user_msgs,
        "total_tool_calls": total_tool_calls,
        "tool_counter": dict(tool_counter),
        "projects_touched": len(projects_touched),
        "first_activity": first_activity,
        "last_activity": last_activity,
        "edited_files": len(edited_files),
        "edited_files_list": sorted(edited_files)[:20],
        "bash_commands_count": len(bash_commands),
        "bash_commands_sample": bash_commands[-10:],
    }


def analyze_git(date_str):
    """워크스페이스 전체 git 활동."""
    since = f"{date_str} 00:00:00"
    until = f"{date_str} 23:59:59"

    commits_by_project = {}
    dirty_by_project = {}
    total_commits = 0
    total_dirty = 0
    total_projects = 0

    for d in sorted(WORKSPACE.iterdir()):
        if not d.is_dir() or not (d / ".git").exists():
            continue
        total_projects += 1
        name = d.name

        try:
            log_result = subprocess.run(
                ["git", "-C", str(d), "log", f"--since={since}", f"--until={until}", "--pretty=format:%h %s"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            if log_result:
                commits = log_result.split("\n")
                commits_by_project[name] = commits
                total_commits += len(commits)

            status = subprocess.run(
                ["git", "-C", str(d), "status", "--porcelain"],
                capture_output=True, text=True, timeout=5
            ).stdout.strip()
            if status:
                count = len(status.splitlines())
                dirty_by_project[name] = count
                total_dirty += count
        except Exception:
            continue

    return {
        "total_projects": total_projects,
        "commits_by_project": commits_by_project,
        "total_commits": total_commits,
        "dirty_by_project": dirty_by_project,
        "total_dirty": total_dirty,
        "projects_with_commits": len(commits_by_project),
        "projects_with_dirty": len(dirty_by_project),
    }


def estimate_tokens(tool_counter):
    """대략적 Claude 토큰 사용량 추정."""
    weights = {
        "Read": 2000,
        "Edit": 1500,
        "Write": 2500,
        "Bash": 800,
        "Grep": 500,
        "Glob": 200,
        "Task": 5000,
        "Agent": 5000,
        "WebFetch": 3000,
        "WebSearch": 2000,
    }
    total = 0
    for tool, count in tool_counter.items():
        total += weights.get(tool, 500) * count
    return total


def compute_session_metrics(sessions, first, last):
    """활동 시간 + 프로젝트 전환 + 집중 블록. first/last는 datetime."""
    if not first or not last:
        return {"active_span_hours": 0, "sessions_count": len(sessions), "unique_projects": 0}

    try:
        duration = (last - first).total_seconds() / 3600
    except Exception:
        duration = 0

    unique_projects = len(set(s["project"] for s in sessions))

    return {
        "active_span_hours": round(duration, 1),
        "sessions_count": len(sessions),
        "unique_projects": unique_projects,
        "first": first.strftime("%Y-%m-%d %H:%M"),
        "last": last.strftime("%Y-%m-%d %H:%M"),
    }


def gemma_evaluate(data, date_str):
    """Gemma에 데이터 넘겨 팩폭 평가 + 내일 우선순위 생성."""
    # Gemma에 넘길 요약본 (토큰 절약)
    summary = {
        "날짜": date_str,
        "활동 시간": data["session_metrics"].get("active_span_hours", 0),
        "세션 수": data["session_metrics"].get("sessions_count", 0),
        "다룬 프로젝트 수": data["session_metrics"].get("unique_projects", 0),
        "첫 활동": data["session_metrics"].get("first", "없음"),
        "마지막 활동": data["session_metrics"].get("last", "없음"),
        "Claude 사용자 메시지": data["sessions"]["total_user_msgs"],
        "도구 호출 총합": data["sessions"]["total_tool_calls"],
        "도구별": data["sessions"]["tool_counter"],
        "수정 파일 수": data["sessions"]["edited_files"],
        "추정 Claude 토큰": data["estimated_tokens"],
        "git 커밋 총합": data["git"]["total_commits"],
        "커밋 있는 프로젝트": data["git"]["projects_with_commits"],
        "미커밋 누적": data["git"]["total_dirty"],
        "미커밋 프로젝트 수": data["git"]["projects_with_dirty"],
        "최다 미커밋 top 5": sorted(data["git"]["dirty_by_project"].items(), key=lambda x: -x[1])[:5],
    }

    prompt = f"""다음은 개발자 leonard의 {date_str} 작업 지표다. 팩폭 있는 일일 리뷰를 작성해라.

데이터:
{json.dumps(summary, ensure_ascii=False, indent=2)}

출력 형식 (정확히 이 구조, 한국어):

## 오늘 평가
<3~5줄. 팩폭 환영. 긍정·부정 균형. 과장 금지.>

## 오늘 잘한 점
- <구체적 1>
- <구체적 2>

## 오늘 아쉬운 점
- <구체적 1>
- <구체적 2>

## 내일 우선순위 (3개)
1. <구체적 행동 + 근거>
2. <구체적 행동 + 근거>
3. <구체적 행동 + 근거>

## 경고 신호
- <있으면 지적, 없으면 "없음">

규칙:
- 데이터 근거만 사용. 없는 내용 추측 금지.
- 단순 칭찬/격려 금지. 구체적 관찰만.
- 이모지 금지.
"""

    try:
        result = call_ollama(
            prompt,
            model="gemma4:e4b",
            num_predict=2000,
            temperature=0.4,
            timeout=90,
            caller="gemma-health-report",
        )
        return result if result else "[Gemma 평가 실패: empty response]"
    except Exception as e:
        return f"[Gemma 평가 실패: {e}]"


def render_report(date_str, data, evaluation):
    """최종 마크다운 리포트."""
    sm = data["session_metrics"]
    s = data["sessions"]
    g = data["git"]

    parts = [
        f"# Leonard 일일 리포트 — {date_str}",
        "",
        f"생성: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "",
        "## 활동 시간",
        f"- 첫 활동: {sm.get('first', '없음')}",
        f"- 마지막 활동: {sm.get('last', '없음')}",
        f"- 활동 스팬: {sm.get('active_span_hours', 0)}시간",
        f"- 세션 수: {sm.get('sessions_count', 0)}",
        f"- 프로젝트 전환: {sm.get('unique_projects', 0)}개",
        "",
        "## AI 사용",
        f"- 사용자 메시지: {s['total_user_msgs']}건",
        f"- 도구 호출: {s['total_tool_calls']}회",
        f"- 수정 파일: {s['edited_files']}개",
        f"- Claude 추정 토큰: {data['estimated_tokens']:,}",
        "",
        "### 도구별 사용",
    ]

    for tool, count in sorted(s["tool_counter"].items(), key=lambda x: -x[1])[:10]:
        parts.append(f"- {tool}: {count}회")

    parts.extend([
        "",
        "## Git 활동",
        f"- 총 프로젝트: {g['total_projects']}개",
        f"- 오늘 커밋한 프로젝트: {g['projects_with_commits']}개",
        f"- 총 커밋: {g['total_commits']}건",
        f"- 미커밋 변경 있는 프로젝트: {g['projects_with_dirty']}개",
        f"- 미커밋 파일 누적: {g['total_dirty']}개",
        "",
    ])

    if g["commits_by_project"]:
        parts.append("### 오늘 커밋 프로젝트")
        for proj, commits in g["commits_by_project"].items():
            parts.append(f"- **{proj}** ({len(commits)}건)")
            for c in commits[:3]:
                parts.append(f"  - {c}")
            if len(commits) > 3:
                parts.append(f"  - ... +{len(commits) - 3}")
        parts.append("")

    if g["dirty_by_project"]:
        top_dirty = sorted(g["dirty_by_project"].items(), key=lambda x: -x[1])[:5]
        parts.append("### 미커밋 상위 5개")
        for proj, count in top_dirty:
            parts.append(f"- {proj}: {count}개 파일")
        parts.append("")

    parts.extend([
        "## Gemma 평가",
        "",
        evaluation,
        "",
        "---",
        "",
        f"_자동 생성: `~/.claude/scripts/gemma-health-report.py`_",
    ])

    return "\n".join(parts)


def main():
    date_str = get_target_date()
    log(f"=== Leonard 일일 리포트 생성 — {date_str} ===")

    # Ollama 확인
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        urllib.request.urlopen(req, timeout=3).read()
    except Exception as e:
        log(f"⚠️ Ollama 접근 불가 — {e}")
        log("   데이터만 수집, 평가 없이 저장")

    log("  1/4 세션 분석 중...")
    sessions = analyze_sessions(date_str)

    log("  2/4 git 활동 분석 중...")
    git_data = analyze_git(date_str)

    log("  3/4 메트릭 계산 중...")
    session_metrics = compute_session_metrics(
        sessions["sessions"], sessions["first_activity"], sessions["last_activity"]
    )
    tokens = estimate_tokens(sessions["tool_counter"])

    data = {
        "sessions": sessions,
        "git": git_data,
        "session_metrics": session_metrics,
        "estimated_tokens": tokens,
    }

    log("  4/4 Gemma 평가 생성 중 (~30초)...")
    evaluation = gemma_evaluate(data, date_str)

    report = render_report(date_str, data, evaluation)
    out_file = OUT_DIR / f"{date_str}.md"
    out_file.write_text(report, encoding="utf-8")

    log(f"\n✅ 저장: {out_file}")
    log(f"\n{'='*60}")
    log(report)


if __name__ == "__main__":
    main()
