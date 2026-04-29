"""backlog 공통 라이브러리

v2 스키마:
    파일 상단에 <!-- schema: v2 --> 마커
    표 컬럼: ID | 제목 | P | 추정 | 상태 | 의존성 | 추가일 | 마감
    "## 상세" 아래에 ID별 세부 내용

v1 스키마 (기존):
    ## 높음/중간/낮음 섹션에 `- [ ]` 또는 `- [x]` 항목
    각 항목은 주 제목 + 들여쓴 메타 (위치, 근거 등)
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Iterator

HOME = Path.home()
WORKSPACE = HOME / "Workspace"

PROJECTS: list[tuple[str, str]] = [
    ("identity-hub", "IH"),
    ("maxai-b2c-backend", "MB"),
    ("identity-keycloak", "IK"),
    ("identity-hub-frontend", "IF"),
    ("identity-hub-python-sdk", "IP"),
    ("keycloak-kakao-social-provider", "KK"),
    ("sso-fallback-monitor", "SF"),
    ("member-api", "MA"),
    ("wb-platform-backend", "WB"),
    ("ai-agentic-workflow", "AW"),
    ("maxai-docker", "MD"),
    ("identity-platform-docker", "ID"),
    ("speakingmax-backend", "SB"),
]

PROJECT_PREFIX = {name: prefix for name, prefix in PROJECTS}
PROJECT_NAMES = [name for name, _ in PROJECTS]

STATUS_VALUES = {"backlog", "active", "review", "done", "blocked"}
PRIORITY_ORDER = {"H": 0, "M": 1, "L": 2}


@dataclass
class Task:
    id: str
    title: str
    priority: str = "M"            # H / M / L
    estimate: str = ""             # 자유 형식: "4h", "1d"
    status: str = "backlog"
    deps: str = ""
    added: str = ""                # YYYY-MM-DD
    due: str = ""                  # YYYY-MM-DD
    detail: list[str] = field(default_factory=list)  # 상세 섹션 줄들

    def to_row(self) -> str:
        cells = [
            self.id,
            self.title.replace("|", r"\|"),
            self.priority,
            self.estimate,
            self.status,
            self.deps,
            self.added,
            self.due,
        ]
        return "| " + " | ".join(cells) + " |"


def read_backlog(path: Path) -> tuple[list[Task], str]:
    """backlog.md 읽어서 (tasks, schema_version) 반환."""
    if not path.exists():
        return [], "none"

    text = path.read_text(encoding="utf-8")
    if "<!-- schema: v2 -->" in text:
        return _parse_v2(text), "v2"
    return _parse_v1(text), "v1"


def _parse_v2(text: str) -> list[Task]:
    tasks: list[Task] = []
    # 표 추출
    table_re = re.compile(
        r"^\| ID \| 제목 \| P \| 추정 \| 상태 \| 의존성 \| 추가일 \| 마감 \|\n"
        r"\|[^\n]+\|\n"
        r"((?:\|[^\n]*\|\n)+)",
        re.MULTILINE,
    )
    m = table_re.search(text)
    if m:
        for row in m.group(1).strip().split("\n"):
            cells = [c.strip() for c in row.strip("|").split("|")]
            if len(cells) != 8:
                continue
            task = Task(
                id=cells[0],
                title=cells[1],
                priority=cells[2] or "M",
                estimate=cells[3],
                status=cells[4] or "backlog",
                deps=cells[5],
                added=cells[6],
                due=cells[7],
            )
            tasks.append(task)

    # 상세 섹션
    detail_re = re.compile(r"^### ([A-Z]+-\d+)\s*[—-]\s*(.+?)$", re.MULTILINE)
    by_id = {t.id: t for t in tasks}
    positions = [(m.group(1), m.start(), m.end()) for m in detail_re.finditer(text)]
    for i, (tid, _, end) in enumerate(positions):
        next_start = positions[i + 1][1] if i + 1 < len(positions) else len(text)
        body = text[end:next_start].strip("\n")
        if tid in by_id:
            by_id[tid].detail = body.split("\n") if body else []
    return tasks


def _parse_v1(text: str) -> list[Task]:
    """기존 포맷 파싱.

    우선순위 섹션:
      - `## 높음 (High)` / `## 중간 (Medium)` / `## 낮음 (Low)`
    각 항목:
      - `- [ ]` 또는 `- [x]` 로 시작
      - 들여쓴 하위 줄은 detail
    """
    tasks: list[Task] = []
    lines = text.split("\n")
    current_priority = "M"
    current_task: Task | None = None

    prio_re = re.compile(r"^##\s+(높음|중간|낮음|High|Medium|Low)")
    item_re = re.compile(r"^-\s+\[( |x|X)\]\s+(.+)$")

    for line in lines:
        # 우선순위 헤더
        m = prio_re.match(line)
        if m:
            label = m.group(1)
            if label in ("높음", "High"):
                current_priority = "H"
            elif label in ("중간", "Medium"):
                current_priority = "M"
            else:
                current_priority = "L"
            continue

        # 새 항목
        m = item_re.match(line)
        if m:
            if current_task:
                tasks.append(current_task)
            checked, raw = m.group(1), m.group(2).strip()
            # `**제목** — 설명` 패턴에서 제목만 추출, 설명은 detail 첫 줄로
            body_detail: list[str] = []
            # 취소선 ~~..~~ 제거
            raw = re.sub(r"~~(.+?)~~", r"\1", raw).strip()
            bold_match = re.match(r"^\*\*(.+?)\*\*\s*[—:-]?\s*(.*)$", raw)
            if bold_match:
                title = bold_match.group(1).strip()
                rest = bold_match.group(2).strip()
                if rest:
                    body_detail.append(rest)
            else:
                # `제목 — 설명` 패턴
                parts = re.split(r"\s+[—-]\s+", raw, maxsplit=1)
                title = parts[0].strip()
                if len(parts) > 1 and parts[1].strip():
                    body_detail.append(parts[1].strip())
            # 제목이 과하게 길면 앞 70자로 자름
            if len(title) > 70:
                title = title[:67] + "..."
            current_task = Task(
                id="",  # migrate 단계에서 부여
                title=title,
                priority=current_priority,
                status="done" if checked in ("x", "X") else "backlog",
                detail=body_detail,
            )
            continue

        # 들여쓴 detail 줄
        if current_task and line.startswith(("  ", "\t")):
            current_task.detail.append(line.strip())

    if current_task:
        tasks.append(current_task)

    return tasks


def render_v2(tasks: list[Task], project_name: str) -> str:
    today = date.today().isoformat()
    lines = [
        "# Backlog",
        "",
        "<!-- schema: v2 -->",
        "",
        f"> 프로젝트: `{project_name}`  ·  총 {len(tasks)}건",
        "",
        "| ID | 제목 | P | 추정 | 상태 | 의존성 | 추가일 | 마감 |",
        "|---|---|---|---|---|---|---|---|",
    ]
    # 상태(backlog 먼저) → 우선순위 순으로 정렬해 표시
    status_order = {"active": 0, "review": 1, "blocked": 2, "backlog": 3, "done": 4}
    sorted_tasks = sorted(
        tasks,
        key=lambda t: (
            status_order.get(t.status, 5),
            PRIORITY_ORDER.get(t.priority, 3),
            t.id,
        ),
    )
    for t in sorted_tasks:
        if not t.added:
            t.added = today
        lines.append(t.to_row())

    lines.extend(["", "## 상세", ""])
    for t in sorted_tasks:
        if t.status == "done" and not t.detail:
            continue
        lines.append(f"### {t.id} — {t.title}")
        if t.detail:
            lines.append("")
            lines.extend(t.detail)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def iter_project_backlogs() -> Iterator[tuple[str, Path]]:
    for name, _prefix in PROJECTS:
        yield name, WORKSPACE / name / "docs" / "backlog.md"


def count_active(project: str) -> int:
    active_dir = WORKSPACE / project / "docs" / "active"
    if not active_dir.is_dir():
        return 0
    return len([p for p in active_dir.glob("*.md") if p.name != ".gitkeep"])


def latest_active_mtime(project: str) -> float | None:
    active_dir = WORKSPACE / project / "docs" / "active"
    archive_dir = WORKSPACE / project / "docs" / "archive"
    candidates = []
    for d in (active_dir, archive_dir):
        if d.is_dir():
            for p in d.rglob("*.md"):
                if p.name != ".gitkeep":
                    candidates.append(p.stat().st_mtime)
    return max(candidates) if candidates else None
