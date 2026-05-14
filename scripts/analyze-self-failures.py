#!/usr/bin/env python3
"""
Claude 자기반성 블랙박스 — 세션 로그에서 Claude 자신의 실패 패턴 추출.

대상 패턴:
1. 추정 후 정정 (assistant가 "아마/추정/~인 듯" → 사용자 정정)
2. 수정→재수정 (같은 파일을 한 세션 내 3+회 Edit/Write)
3. 테스트 안 돌리고 완료선언 (assistant "완료/끝났/성공" → 직전 30분 test 미실행)
4. 사용자 정정 패턴 ("아니/틀렸/그게 아니라/다시 해/수정해")

출력: ~/.claude/self-model/{project}.md, ~/.claude/self-model/_global.md
"""

import json
import re
import sys
import argparse
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime, timezone

PROJECTS_DIR = Path.home() / ".claude/projects"
OUT_DIR = Path.home() / ".claude/self-model"

ASSUMPTION_PATTERNS = re.compile(
    r"(아마|추정|~인 듯|일 것|일거 같|것 같|아닌가|싶|maybe|probably|should be|i think)",
    re.IGNORECASE
)
COMPLETION_PATTERNS = re.compile(
    r"(완료|완성|끝났|성공|done|completed|finished|all set)",
    re.IGNORECASE
)
USER_CORRECTION_PATTERNS = re.compile(
    r"(아니|틀렸|그게 아니|다시 해|다시해|수정해|틀린|잘못|nope|wrong|incorrect|fix that)",
    re.IGNORECASE
)
TEST_RUN_PATTERNS = re.compile(
    r"\b(pytest|jest|npm test|npm run test|go test|cargo test|mvn test|gradle test|phpunit|rspec|vitest)\b",
    re.IGNORECASE
)


def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                t = item.get("type")
                if t == "text":
                    parts.append(item.get("text", ""))
                elif t == "thinking":
                    parts.append(item.get("thinking", ""))
                elif t == "tool_use":
                    inp = item.get("input", {})
                    parts.append(f"[tool_use:{item.get('name','?')}] {json.dumps(inp, ensure_ascii=False)[:500]}")
                elif t == "tool_result":
                    parts.append(f"[tool_result] {str(item.get('content',''))[:300]}")
        return "\n".join(parts)
    return str(content)


def parse_session(jsonl_path):
    msgs = []
    try:
        with open(jsonl_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                t = d.get("type")
                if t not in ("user", "assistant"):
                    continue
                msg = d.get("message", {}) or {}
                role = msg.get("role") or t
                content = msg.get("content", "")
                text = extract_text(content)
                ts = d.get("timestamp") or d.get("createdAt") or ""
                msgs.append({
                    "role": role,
                    "text": text,
                    "ts": ts,
                    "raw_content": content,
                })
    except FileNotFoundError:
        return []
    return msgs


def detect_patterns(msgs, project):
    findings = {
        "assumption_then_correction": [],
        "completion_without_test": [],
        "user_correction": [],
        "repeated_edits": [],
    }

    file_edit_count = Counter()
    last_test_run_idx = -100

    for i, m in enumerate(msgs):
        text = m["text"] or ""
        role = m["role"]

        if role == "assistant" and TEST_RUN_PATTERNS.search(text):
            last_test_run_idx = i

        if role == "assistant" and isinstance(m["raw_content"], list):
            for item in m["raw_content"]:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    tool = item.get("name", "")
                    if tool in ("Edit", "Write", "MultiEdit"):
                        fp = (item.get("input", {}) or {}).get("file_path", "")
                        if fp:
                            file_edit_count[fp] += 1

        if role == "assistant" and not is_meta and ASSUMPTION_PATTERNS.search(text):
            for j in range(i + 1, min(i + 5, len(msgs))):
                user_text = msgs[j]["text"] or ""
                user_is_paste = bool(re.match(r"^(Base directory for this skill|<system-reminder|---\nname:)", user_text, re.MULTILINE)) or user_text.count("\n") > 10
                if msgs[j]["role"] == "user" and not user_is_paste and USER_CORRECTION_PATTERNS.search(user_text):
                    findings["assumption_then_correction"].append({
                        "ts": m["ts"],
                        "assumption_excerpt": (text[:200]).replace("\n", " "),
                        "correction_excerpt": (user_text[:200]).replace("\n", " "),
                    })
                    break

        # tool_use:TaskUpdate 같은 시스템 메타 발화 제외
        is_meta = bool(re.match(r"^\s*\[tool_(use|result):", text or ""))

        if role == "assistant" and not is_meta and COMPLETION_PATTERNS.search(text):
            # "완료" 단어가 짧은 메시지나 명사구가 아닌 실제 완료 선언인지
            if len(text) > 30 and i - last_test_run_idx > 20:
                findings["completion_without_test"].append({
                    "ts": m["ts"],
                    "claim_excerpt": (text[:200]).replace("\n", " "),
                    "msgs_since_last_test": i - last_test_run_idx,
                })

        # skill invoke 결과/시스템 reminder/긴 인용은 사용자 정정 아님
        is_skill_paste = bool(re.match(r"^(Base directory for this skill|<system-reminder|---\nname:|##? )", text or "", re.MULTILINE))
        is_long_paste = (text or "").count("\n") > 10  # 10줄 이상 붙여넣기는 정정 아님

        if role == "user" and USER_CORRECTION_PATTERNS.search(text) and not is_skill_paste and not is_long_paste:
            prev_idx = i - 1
            while prev_idx >= 0 and msgs[prev_idx]["role"] != "assistant":
                prev_idx -= 1
            if prev_idx >= 0:
                # 직전 답변이 메타(tool_use)이면 제외
                prev_text = msgs[prev_idx]["text"] or ""
                if re.match(r"^\s*\[tool_(use|result):", prev_text):
                    continue
                findings["user_correction"].append({
                    "ts": m["ts"],
                    "user_excerpt": (text[:200]).replace("\n", " "),
                    "prev_assistant_excerpt": (prev_text[:200]).replace("\n", " "),
                })

    for fp, cnt in file_edit_count.items():
        if cnt >= 3:
            findings["repeated_edits"].append({
                "file": fp,
                "edit_count": cnt,
            })

    return findings


def write_self_model(project, all_findings, sessions_count):
    total_patterns = sum(len(v) for v in all_findings.values())
    out_path = OUT_DIR / f"{project}.md"

    lines = []
    lines.append("---")
    lines.append(f"project: {project}")
    lines.append(f"generated_at: {datetime.now(timezone.utc).isoformat()}")
    lines.append(f"sessions_analyzed: {sessions_count}")
    lines.append(f"patterns_detected: {total_patterns}")
    lines.append("---")
    lines.append("")
    lines.append(f"# Claude Self-Model: {project}")
    lines.append("")
    lines.append(f"**세션 분석**: {sessions_count}개 세션, {total_patterns}개 패턴 감지")
    lines.append("")

    section_titles = {
        "assumption_then_correction": "1. 추정 후 사용자 정정 (가장 흔함)",
        "completion_without_test": "2. 테스트 안 돌리고 완료 선언",
        "user_correction": "3. 사용자 정정 발생 직전 답변",
        "repeated_edits": "4. 한 세션 내 같은 파일 반복 수정 (3회+)",
    }

    for key, title in section_titles.items():
        items = all_findings.get(key, [])
        if not items:
            continue
        lines.append(f"## {title} ({len(items)}회)")
        lines.append("")
        for item in items[:8]:
            ts = item.get("ts", "")[:16] or "?"
            if key == "assumption_then_correction":
                lines.append(f"- **{ts}**")
                lines.append(f"  - 추정: `{item['assumption_excerpt']}`")
                lines.append(f"  - 정정: `{item['correction_excerpt']}`")
            elif key == "completion_without_test":
                lines.append(f"- **{ts}** — 마지막 테스트 후 {item['msgs_since_last_test']}개 메시지")
                lines.append(f"  - 주장: `{item['claim_excerpt']}`")
            elif key == "user_correction":
                lines.append(f"- **{ts}**")
                lines.append(f"  - 직전 답변: `{item['prev_assistant_excerpt']}`")
                lines.append(f"  - 사용자 정정: `{item['user_excerpt']}`")
            elif key == "repeated_edits":
                lines.append(f"- `{item['file']}` — {item['edit_count']}회 수정")
        if len(items) > 8:
            lines.append(f"- ... 외 {len(items)-8}건")
        lines.append("")

    lines.append("## 답변 전 자기 점검 체크리스트")
    lines.append("")
    if all_findings.get("assumption_then_correction"):
        lines.append("- [ ] 사실 단언 전, Grep/Read로 코드를 직접 확인했는가? (추정→정정 패턴 빈발)")
    if all_findings.get("completion_without_test"):
        lines.append("- [ ] '완료' 선언 전, 실제 테스트를 실행하고 결과를 확인했는가?")
    if all_findings.get("repeated_edits"):
        lines.append("- [ ] 같은 파일을 반복 수정 중이면, 더 큰 설계 문제가 없는지 점검했는가?")
    if all_findings.get("user_correction"):
        lines.append("- [ ] 답변 직후 사용자가 정정하는 패턴이 보임 — 첫 답에 더 깊이 검증 필요")
    lines.append("")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
    return out_path, total_patterns


def write_global_summary(per_project_stats):
    out_path = OUT_DIR / "_global.md"
    lines = []
    lines.append("---")
    lines.append(f"generated_at: {datetime.now(timezone.utc).isoformat()}")
    lines.append(f"projects: {len(per_project_stats)}")
    lines.append("---")
    lines.append("")
    lines.append("# Claude 자기반성 블랙박스 — 전체 요약")
    lines.append("")
    lines.append("| 프로젝트 | 세션 | 추정→정정 | 테스트미실행완료 | 사용자정정 | 반복수정 |")
    lines.append("|---|---|---|---|---|---|")
    for p, s in sorted(per_project_stats.items(), key=lambda x: -sum(x[1].get(k, 0) for k in ("assumption_then_correction","completion_without_test","user_correction","repeated_edits"))):
        lines.append(
            f"| {p} | {s.get('sessions',0)} "
            f"| {s.get('assumption_then_correction',0)} "
            f"| {s.get('completion_without_test',0)} "
            f"| {s.get('user_correction',0)} "
            f"| {s.get('repeated_edits',0)} |"
        )
    lines.append("")
    lines.append("## TOP 실패 카테고리")
    lines.append("")
    cat_total = defaultdict(int)
    for s in per_project_stats.values():
        for k in ("assumption_then_correction","completion_without_test","user_correction","repeated_edits"):
            cat_total[k] += s.get(k, 0)
    for k, v in sorted(cat_total.items(), key=lambda x: -x[1]):
        lines.append(f"- **{k}**: {v}회")

    out_path.write_text("\n".join(lines), encoding="utf-8")
    return out_path


def project_name_from_dir(dir_name):
    if dir_name.startswith("-Users-leonard-Workspace-"):
        return dir_name[len("-Users-leonard-Workspace-"):]
    if dir_name.startswith("-Users-leonard-"):
        return dir_name[len("-Users-leonard-"):]
    return dir_name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", help="단일 프로젝트만 분석")
    ap.add_argument("--dry-run", action="store_true", help="파일 저장 안 하고 통계만 출력")
    ap.add_argument("--max-sessions", type=int, default=50, help="프로젝트당 최대 세션 (최근순)")
    args = ap.parse_args()

    if not PROJECTS_DIR.exists():
        print(f"세션 디렉토리 없음: {PROJECTS_DIR}", file=sys.stderr)
        sys.exit(1)

    per_project_stats = {}
    target_dirs = []

    for d in sorted(PROJECTS_DIR.iterdir()):
        if not d.is_dir():
            continue
        proj = project_name_from_dir(d.name)
        if args.project and args.project != proj:
            continue
        target_dirs.append((proj, d))

    print(f"분석 대상: {len(target_dirs)} 프로젝트", file=sys.stderr)

    for proj, d in target_dirs:
        jsonls = sorted(d.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:args.max_sessions]
        if not jsonls:
            continue

        agg = defaultdict(list)
        for jp in jsonls:
            msgs = parse_session(jp)
            if not msgs:
                continue
            findings = detect_patterns(msgs, proj)
            for k, v in findings.items():
                agg[k].extend(v)

        stats = {k: len(agg.get(k, [])) for k in ("assumption_then_correction","completion_without_test","user_correction","repeated_edits")}
        stats["sessions"] = len(jsonls)
        per_project_stats[proj] = stats

        total = sum(stats[k] for k in ("assumption_then_correction","completion_without_test","user_correction","repeated_edits"))
        print(f"  {proj}: {len(jsonls)}세션, 패턴 {total}개", file=sys.stderr)

        if not args.dry_run and total > 0:
            out_path, _ = write_self_model(proj, dict(agg), len(jsonls))

    if not args.dry_run and per_project_stats:
        gp = write_global_summary(per_project_stats)
        print(f"\n전체 요약: {gp}", file=sys.stderr)

    print(json.dumps(per_project_stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
