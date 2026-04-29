#!/usr/bin/env python3
"""
knowledge-index.json 의 요약 정보를 knowledge-catalog.md 에 녹여서 개선된 카탈로그 생성.

Before (기존):
| 1 | `01-api-design` | API 설계 | 245줄 |

After (개선):
| 1 | `01-api-design` | API 설계 | 245줄 | REST URL/HTTP 메서드/에러 응답/버전 관리 다룸 | REST, HTTP, 페이징 |

에이전트가 카탈로그만 읽어도 "이 파일이 필요한지" 즉시 판단 가능.

- 원본 백업: knowledge-catalog.md.bak
- 출력: knowledge-catalog.md (원본 자리 대체)
- 대체본 위치 공지: knowledge-catalog.enhanced.md (부가본도 남김)
"""
import json
import os
import re
import sys
from pathlib import Path
from collections import defaultdict

KB_ROOT = Path.home() / ".claude" / "agents" / "knowledge"
INDEX_FILE = Path.home() / ".claude" / "cache" / "knowledge-index.json"
CATALOG = KB_ROOT / "knowledge-catalog.md"
BACKUP = KB_ROOT / "knowledge-catalog.md.bak"
ENHANCED = KB_ROOT / "knowledge-catalog.enhanced.md"

ROLE_DISPLAY = {
    "po": "📋 Product Owner",
    "frontend-developer": "🕸 Frontend Developer",
    "backend-developer": "⚙️ Backend Developer",
    "code-reviewer": "🔍 Code Reviewer",
    "code-tester": "🧪 Code Tester",
    "qa": "✅ QA",
    "designer": "🎨 Designer",
    "data-analyst": "📊 Data Analyst",
    "ai-engineer": "🤖 AI Engineer",
    "ops-lead": "🗂 Operations Lead",
    "prompt-engineer": "💬 Prompt Engineer",
}


def log(msg):
    print(msg, flush=True)


def load_index():
    if not INDEX_FILE.exists():
        log(f"ERR: {INDEX_FILE} 없음 — 인덱싱 미완")
        return None
    try:
        return json.loads(INDEX_FILE.read_text())
    except Exception as e:
        log(f"ERR: 인덱스 파싱 실패 — {e}")
        return None


def group_by_role(index):
    grouped = defaultdict(list)
    for rel, entry in index.items():
        role = entry.get("role", "")
        if not role:
            # path에서 역할 추출
            role = rel.split("/")[0]
        grouped[role].append((rel, entry))
    # 각 역할 내에서 파일명 정렬
    for role in grouped:
        grouped[role].sort(key=lambda x: x[0])
    return grouped


def count_lines(path: Path) -> int:
    try:
        return sum(1 for _ in path.open(encoding="utf-8", errors="replace"))
    except Exception:
        return 0


def render_enhanced_catalog(index):
    grouped = group_by_role(index)
    total_files = sum(len(v) for v in grouped.values())

    lines = [
        "# Knowledge 카탈로그 (개선판)",
        "",
        "자동 생성: knowledge-index.json 기반 Gemma 요약 포함.",
        "각 문서에 한 줄 요약 + 키워드가 붙어 있어, 에이전트가 카탈로그만 봐도 어떤 파일을 Read할지 판단 가능.",
        "",
        f"> 총 {total_files}개 파일 · {len(grouped)}개 역할 카테고리",
        "",
        "---",
        "",
    ]

    # 역할 순서: ROLE_DISPLAY 순서 먼저, 그 외는 알파벳
    ordered_roles = [r for r in ROLE_DISPLAY if r in grouped]
    extra_roles = sorted(r for r in grouped if r not in ROLE_DISPLAY)
    all_roles = ordered_roles + extra_roles

    for role in all_roles:
        items = grouped[role]
        display = ROLE_DISPLAY.get(role, role)
        total_lines_role = 0
        rows = []

        for rel, entry in items:
            fp = KB_ROOT / rel
            lc = count_lines(fp)
            total_lines_role += lc
            # 파일명 (확장자 제거)
            fname = Path(rel).stem
            title = entry.get("title", "").strip() or fname
            summary = entry.get("summary", "").strip().replace("\n", " ").replace("|", "／")
            keywords = ", ".join(entry.get("keywords", [])[:6])
            # 길이 컷
            if len(summary) > 90:
                summary = summary[:87] + "…"
            if len(keywords) > 60:
                keywords = keywords[:57] + "…"
            rows.append(
                f"| `{fname}` | {title} | {lc}줄 | {summary} | {keywords} |"
            )

        lines.append(f"## {display} ({len(items)}개 · {total_lines_role}줄)")
        lines.append("")
        lines.append("| 파일 | 제목 | 줄 수 | 요약 | 키워드 |")
        lines.append("| --- | --- | --- | --- | --- |")
        lines.extend(rows)
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## 사용 가이드 (에이전트용)")
    lines.append("")
    lines.append("1. 태스크 받으면 이 카탈로그의 요약 열을 훑어 **관련성 높은 2~3개** 파일 식별")
    lines.append("2. 해당 파일만 Read — 전체 knowledge 디렉토리 훑지 말 것")
    lines.append("3. 키워드 열로 검색 가능: 예) `REST`, `인덱스`, `A/B`")
    lines.append("")
    return "\n".join(lines)


def main():
    index = load_index()
    if not index:
        return 1

    log(f"인덱스 항목 {len(index)}개 로드")

    # 유효성 체크
    valid = sum(1 for e in index.values() if e.get("title") and e.get("summary"))
    log(f"유효 항목 {valid}/{len(index)}")

    if valid < len(index) * 0.8:
        log(f"⚠️ 유효율 {valid/len(index)*100:.0f}% — 80% 미만이라 업그레이드 중단")
        log("  먼저 gemma-knowledge-retry.py 재실행 권장")
        return 2

    # 백업
    if CATALOG.exists() and not BACKUP.exists():
        BACKUP.write_text(CATALOG.read_text(encoding="utf-8"), encoding="utf-8")
        log(f"기존 카탈로그 백업: {BACKUP}")

    enhanced = render_enhanced_catalog(index)

    # 원본 자리에 쓸지, 별도 파일로 남길지: 둘 다
    ENHANCED.write_text(enhanced, encoding="utf-8")
    log(f"개선 카탈로그 저장: {ENHANCED}")

    # 원본도 개선본으로 대체 (에이전트가 knowledge-catalog.md를 참조하므로)
    CATALOG.write_text(enhanced, encoding="utf-8")
    log(f"원본 카탈로그 대체: {CATALOG}")
    log(f"(원본은 {BACKUP} 에 백업됨)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
