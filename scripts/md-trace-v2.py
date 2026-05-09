#!/usr/bin/env python3
"""md-trace v2: 메타 라우팅 관측성 대시보드.

v1(Sankey)과 달리 다음 4가지 질문에 답한다:
  (a) 어떤 요청 카테고리가 어떤 컨텍스트(.md 카테고리)를 끌어왔나 — Heatmap
  (b) 어떤 룰이 잘 작동/안 작동하나 — 적중률 (감지된 트리거 vs 실제 Read)
  (c) 어떤 .md가 죽었나 (Read 0회) — 죽은 룰 패널
  (d) 시간 추이 — 14일 lane 타임라인

데이터 소스: ~/.claude/projects/**/*.jsonl
출력: ~/.claude/cache/md-trace/report-v2.html (Plotly CDN, 단일 HTML)
"""
import argparse
import html
import json
import re
import sys
import time
import webbrowser
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
PROJECTS_DIR = HOME / ".claude" / "projects"
OUT_DIR = HOME / ".claude" / "cache" / "md-trace"
CLAUDE_ROOT = HOME / ".claude"

SYSTEM_PATTERNS = [
    re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL),
    re.compile(r"<command-message>.*?</command-message>", re.DOTALL),
    re.compile(r"<command-name>.*?</command-name>", re.DOTALL),
    re.compile(r"<local-command-stdout>.*?</local-command-stdout>", re.DOTALL),
    re.compile(r"<bash-input>.*?</bash-input>", re.DOTALL),
    re.compile(r"<bash-stdout>.*?</bash-stdout>", re.DOTALL),
    re.compile(r"<bash-stderr>.*?</bash-stderr>", re.DOTALL),
    re.compile(r"<user-prompt-submit-hook>.*?</user-prompt-submit-hook>", re.DOTALL),
    re.compile(r"<task-notification>.*?</task-notification>", re.DOTALL),
]

# 요청 카테고리 분류 — CLAUDE.md "작업 타입 자동 라우팅" + "단축 호출" + "한글 에이전트" 합성.
# (키워드, 카테고리, 기대되는 .md 글롭 패턴들)
REQUEST_RULES = [
    # 작업 타입 (standard-routines.md)
    (r"기능\s*추가|새\s*기능|new\s*feature\b|새로\s*만들어", "feature", ["workflows/standard-routines.md"]),
    (r"버그|에러|오류|fix\b|안\s*돼|실패|디버그", "bugfix", ["workflows/debugging.md"]),
    (r"리팩터|정리|구조\s*개선|refactor", "refactor", ["workflows/standard-routines.md"]),
    (r"UI|화면|디자인|스타일|css|레이아웃", "design", []),
    (r"쿼리|대시보드|분석|ClickHouse|sql\b|메트릭", "data", []),
    (r"배포|Docker|Terraform|SPI|deploy|infra", "ops", ["workflows/standard-routines.md"]),
    (r"문서|PRD|스펙|정리하|markdown", "docs", ["workflows/docs-convention.md"]),
    # 도메인
    (r"SSO|Identity\s*Hub|keycloak|B2C|JWT", "sso", ["workflows/sso.md"]),
    (r"파이프라인|pipeline", "pipeline", ["workflows/pipeline.md"]),
    (r"코딩\s*컨벤션|네이밍|코딩\s*스타일", "convention", ["workflows/coding-convention.md"]),
    (r"학습|회고|성장|deep[- ]?learn", "growth", ["workflows/growth.md"]),
    # LLM/도구 호출
    (r"\bcodex\b|gpt-?5|second\s*opinion|세컨드\s*오피니언", "codex", ["workflows/codex.md"]),
    (r"\bgemini\b|1M\s*토큰|gemini\s*-?p", "gemini", ["workflows/llm-routing.md"]),
    (r"\bollama\b|gemma|qwen", "ollama", ["workflows/llm-routing.md"]),
    # 메타
    (r"훅|hook|자동화|automation", "automation", ["workflows/automation.md"]),
    (r"백로그|backlog", "backlog", ["workflows/standard-routines.md"]),
    # 한글 에이전트 호출
    (r"^@dev\b|^백엔드|^프론트|^AI엔지니어|^테스터|^리뷰어|^큐에이|^디자이너|^피오|^데이터|^옵스", "agent_call", []),
    # 시각화/관측성 (이번 md-trace 자체)
    (r"시각화|대시보드|chart|sankey|heatmap|관측성", "visualization", []),
]

# .md 카테고리 색상 (디자이너 추천 톤)
CAT_COLORS = {
    "workflows": "#F58518",
    "skills":    "#54A24B",
    "agents":    "#B279A2",
    "memory":    "#EECA3B",
    "plugins":   "#9D755D",
    "CLAUDE.md": "#E45756",
    "project":   "#72B7B2",
    "other":     "#BAB0AC",
}


def clean_prompt(text: str) -> str:
    for pat in SYSTEM_PATTERNS:
        text = pat.sub("", text)
    return text.strip()


def relpath_md(file_path: str) -> str:
    p = Path(file_path)
    try:
        return str(p.relative_to(CLAUDE_ROOT))
    except ValueError:
        return str(p)


def categorize_md(rel: str) -> str:
    if rel.startswith("workflows/"): return "workflows"
    if rel.startswith("skills/"):    return "skills"
    if rel.startswith("agents/"):    return "agents"
    if "memory/" in rel and rel.startswith("projects/"): return "memory"
    if rel.startswith("plugins/"):   return "plugins"
    if rel == "CLAUDE.md" or rel.endswith("/CLAUDE.md"): return "CLAUDE.md"
    if rel.startswith("/"):          return "project"
    return "other"


def is_in_scope(rel: str, scope: str) -> bool:
    if scope == "all":    return True
    if scope == "claude": return not rel.startswith("/")
    if scope == "config":
        return categorize_md(rel) in {"workflows", "skills", "agents", "memory", "CLAUDE.md"}
    return True


def categorize_request(prompt: str) -> tuple[list[str], list[str]]:
    """요청 텍스트에서 카테고리 + 기대 .md 글롭 추출.

    하나의 요청은 여러 카테고리 동시 매칭 가능 (예: 'SSO 버그' → bugfix + sso).
    매칭 없으면 ['general']."""
    cats, expected = [], []
    p = prompt.lower()
    for pat, cat, exps in REQUEST_RULES:
        if re.search(pat, prompt, re.IGNORECASE):
            cats.append(cat)
            expected.extend(exps)
    if not cats:
        cats = ["general"]
    return cats, expected


def discover_all_md(scope: str) -> list[str]:
    """~/.claude 안에 존재하는 모든 관리 대상 .md 수집 (죽은 룰 탐지용).

    범위: workflows/, skills/, agents/, memory/, CLAUDE.md
    """
    found: set[str] = set()
    targets = [
        CLAUDE_ROOT / "CLAUDE.md",
        *CLAUDE_ROOT.glob("workflows/*.md"),
        *CLAUDE_ROOT.glob("skills/*/skill.md"),
        *CLAUDE_ROOT.glob("skills/*/SKILL.md"),
        *CLAUDE_ROOT.glob("agents/*.md"),
        *CLAUDE_ROOT.glob("projects/*/memory/*.md"),
    ]
    for p in targets:
        if not p.exists():
            continue
        rel = relpath_md(str(p))
        if is_in_scope(rel, scope):
            found.add(rel)
    return sorted(found)


def iter_user_turns(jsonl_path: Path):
    current = {"prompt": None, "ts": None, "reads": []}

    with jsonl_path.open("r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue

            rtype = rec.get("type")
            if rtype == "user":
                if rec.get("userType") != "external":
                    continue
                msg = rec.get("message") or {}
                content = msg.get("content")
                # tool_result 가 섞여있는 user record 는 사용자 발화가 아님 — Read 윈도우 유지
                is_tool_result = (isinstance(content, list)
                                  and any(isinstance(c, dict) and c.get("type") == "tool_result"
                                          for c in content))
                if is_tool_result:
                    continue
                text = ""
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    parts = []
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            parts.append(c.get("text", ""))
                    text = "\n".join(parts)
                cleaned = clean_prompt(text)
                if not cleaned:
                    continue
                if current["prompt"] is not None:
                    yield current["prompt"], current["ts"], list(current["reads"])
                current = {"prompt": cleaned, "ts": rec.get("timestamp", ""), "reads": []}
            elif rtype == "assistant" and current["prompt"] is not None:
                msg = rec.get("message") or {}
                content = msg.get("content")
                if isinstance(content, list):
                    for c in content:
                        if (isinstance(c, dict) and c.get("type") == "tool_use"
                                and c.get("name") == "Read"):
                            fp = (c.get("input") or {}).get("file_path")
                            if isinstance(fp, str) and fp.endswith(".md"):
                                current["reads"].append(fp)
        if current["prompt"] is not None:
            yield current["prompt"], current["ts"], list(current["reads"])


def collect(days: int, scope: str):
    cutoff = time.time() - days * 86400
    files = [p for p in PROJECTS_DIR.rglob("*.jsonl")
             if p.stat().st_mtime >= cutoff]

    turns = []
    for p in sorted(files, key=lambda x: x.stat().st_mtime):
        for prompt, ts, reads in iter_user_turns(p):
            md_reads = [relpath_md(r) for r in reads]
            md_reads = [m for m in md_reads if is_in_scope(m, scope)]
            cats, expected = categorize_request(prompt)
            turns.append({
                "prompt": prompt,
                "ts": ts,
                "session": p.stem,
                "reads": md_reads,
                "cats": cats,
                "expected": list(set(expected)),
            })
    return files, turns


AGENT_CALL_RE = re.compile(r"^\s*(@dev|@team|백엔드|프론트|AI엔지니어|테스터|리뷰어|큐에이|디자이너|피오|데이터|옵스|프롬프트)\b")
AUTOLOAD_PATTERNS = ("CLAUDE.md", "agents/dev.md", "agents/team.md")


def classify_mode(prompt: str, expected: list[str]) -> str:
    """발화를 3모드로 분류 — 라우팅 측정 단위.

    - agent_call: @dev / 한글 에이전트 호출 (자체 라우팅 — 적중률 측정 제외)
    - keyword: REQUEST_RULES 의 expected 글롭이 매칭된 명시적 트리거
    - autoload: 그 외 (자동 메모리/CLAUDE.md 로딩이 주된 .md Read 원인)
    """
    if AGENT_CALL_RE.search(prompt):
        return "agent_call"
    if expected:
        return "keyword"
    return "autoload"


def compute_metrics(turns, all_md):
    """3모드 분리 KPI.

    - 자동로딩 모드: CLAUDE.md/agents 자동 로딩이 일어났는지 (auto_md 매칭률)
    - 에이전트 호출 모드: agents/<name>.md 가 실제 Read 되었는지
    - 키워드 모드: REQUEST_RULES expected 매칭률 (구 적중률)
    + 죽은 룰 비율, expected 미정의 룰 비율
    """
    by_mode = {"autoload": [], "agent_call": [], "keyword": []}
    misses = []  # keyword 모드 갭만 수집

    for t in turns:
        m = classify_mode(t["prompt"], t["expected"])
        t["mode"] = m
        by_mode[m].append(t)

    # 키워드 모드 적중률
    kw_total = len(by_mode["keyword"])
    kw_hit = 0
    for t in by_mode["keyword"]:
        reads = set(t["reads"])
        if reads & set(t["expected"]):
            kw_hit += 1
        else:
            misses.append({
                "prompt": t["prompt"][:120], "ts": t["ts"],
                "cats": t["cats"], "expected": t["expected"], "actual": t["reads"],
            })
    kw_rate = (kw_hit / kw_total * 100) if kw_total else None

    # 에이전트 호출 모드 — agents/*.md 가 한 번이라도 읽혔나
    ac_total = len(by_mode["agent_call"])
    ac_hit = sum(1 for t in by_mode["agent_call"]
                 if any(r.startswith("agents/") for r in t["reads"]))
    ac_rate = (ac_hit / ac_total * 100) if ac_total else None

    # 자동로딩 모드 — CLAUDE.md/MEMORY.md 가 읽혔나 (없는 게 정상은 아님)
    al_total = len(by_mode["autoload"])
    al_hit = sum(1 for t in by_mode["autoload"]
                 if any(p in r for r in t["reads"] for p in AUTOLOAD_PATTERNS)
                 or any("memory/" in r for r in t["reads"]))
    al_rate = (al_hit / al_total * 100) if al_total else None

    # 세션 단위 적중률 — Claude는 한 번 읽은 .md 를 세션 캐시함. 발화별 매칭은 과소 추정.
    sess_keyword = defaultdict(lambda: {"expected": set(), "reads": set()})
    for t in turns:
        if not t["expected"]:
            continue
        s = t.get("session", "?")
        sess_keyword[s]["expected"].update(t["expected"])
        sess_keyword[s]["reads"].update(t["reads"])
    sess_kw_total = len(sess_keyword)
    sess_kw_hit = sum(1 for v in sess_keyword.values() if v["expected"] & v["reads"])
    sess_kw_rate = (sess_kw_hit / sess_kw_total * 100) if sess_kw_total else None

    # expected 미정의 룰 비율 (REQUEST_RULES 메타 진단)
    total_rules = len(REQUEST_RULES)
    rules_no_expected = sum(1 for _, _, exps in REQUEST_RULES if not exps)
    no_exp_rate = rules_no_expected / total_rules * 100 if total_rules else 0

    # 죽은 룰 비율
    seen = {r for t in turns for r in t["reads"]}
    dead_rate = (sum(1 for md in all_md if md not in seen) / len(all_md) * 100) if all_md else 0

    return {
        "kw_rate": kw_rate, "kw_hit": kw_hit, "kw_total": kw_total,
        "sess_kw_rate": sess_kw_rate, "sess_kw_hit": sess_kw_hit, "sess_kw_total": sess_kw_total,
        "ac_rate": ac_rate, "ac_hit": ac_hit, "ac_total": ac_total,
        "al_rate": al_rate, "al_hit": al_hit, "al_total": al_total,
        "no_exp_rate": no_exp_rate, "rules_no_expected": rules_no_expected, "total_rules": total_rules,
        "dead_rate": dead_rate,
        "misses": misses,
    }


def build_heatmap(turns):
    """행=요청 카테고리, 열=md 카테고리, 셀=참조 횟수."""
    matrix = defaultdict(lambda: defaultdict(int))
    md_categories = ["workflows", "skills", "agents", "memory", "CLAUDE.md", "plugins", "project", "other"]
    req_cat_counts: Counter = Counter()
    drilldown = defaultdict(lambda: defaultdict(list))

    for t in turns:
        for rcat in t["cats"]:
            req_cat_counts[rcat] += 1
            for md in t["reads"]:
                mcat = categorize_md(md)
                matrix[rcat][mcat] += 1
                drilldown[rcat][mcat].append({
                    "md": md, "prompt": t["prompt"][:120], "ts": t["ts"],
                })

    req_cats = [c for c, _ in req_cat_counts.most_common()]
    z = [[matrix[r].get(m, 0) for m in md_categories] for r in req_cats]
    text = [[(matrix[r].get(m, 0) or "") for m in md_categories] for r in req_cats]
    return {
        "x": md_categories,
        "y": req_cats,
        "z": z,
        "text": text,
        "drilldown": {r: {m: drilldown[r][m] for m in md_categories} for r in req_cats},
        "req_counts": dict(req_cat_counts),
    }


def find_dead(all_md, turns):
    seen = Counter()
    for t in turns:
        for m in t["reads"]:
            seen[m] += 1
    dead = []
    alive = []
    for md in all_md:
        if md not in seen:
            dead.append({"md": md, "cat": categorize_md(md)})
        else:
            alive.append({"md": md, "cat": categorize_md(md), "count": seen[md]})
    alive.sort(key=lambda x: -x["count"])
    return dead, alive


def build_timeline(turns, days):
    """일 × 요청 카테고리 lane."""
    lanes = defaultdict(lambda: defaultdict(int))
    for t in turns:
        try:
            d = datetime.fromisoformat(t["ts"].replace("Z", "+00:00")).date().isoformat()
        except (ValueError, AttributeError):
            continue
        for rcat in t["cats"]:
            lanes[rcat][d] += 1
    all_dates = sorted({d for lane in lanes.values() for d in lane})
    return {
        "dates": all_dates,
        "lanes": [
            {
                "cat": rcat,
                "values": [lanes[rcat].get(d, 0) for d in all_dates],
            }
            for rcat in sorted(lanes.keys(), key=lambda c: -sum(lanes[c].values()))
        ],
    }


def render_html(payload, out_path: Path, font: int, height: int):
    doc = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<title>md-trace v2 · 메타 라우팅 관측성</title>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<style>
 :root {{ --fg:#222; --muted:#666; --bg:#fafafa; --panel:#fff; --border:#e5e5e5; --accent:#4C78A8; }}
 *{{box-sizing:border-box}}
 body{{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;margin:18px;background:var(--bg);color:var(--fg);font-size:{font}px}}
 h1{{margin:0 0 4px 0;font-size:{font+8}px}}
 .meta{{color:var(--muted);font-size:{font-1}px;margin-bottom:12px}}
 .health{{display:flex;gap:14px;flex-wrap:wrap;background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:14px 18px;margin-bottom:16px}}
 .kpi{{display:flex;flex-direction:column;align-items:flex-start;min-width:120px}}
 .kpi .v{{font-size:{font+14}px;font-weight:600;color:var(--accent);font-variant-numeric:tabular-nums}}
 .kpi .l{{font-size:{font-1}px;color:var(--muted)}}
 .kpi.warn .v{{color:#E45756}}
 .kpi.good .v{{color:#54A24B}}
 .controls{{display:flex;flex-wrap:wrap;gap:14px;align-items:center;background:var(--panel);border:1px solid var(--border);border-radius:8px;padding:8px 14px;margin-bottom:14px;font-size:{font-1}px}}
 .controls input[type=range]{{width:120px}}
 .controls .val{{display:inline-block;min-width:38px;text-align:right;color:var(--muted);font-variant-numeric:tabular-nums}}
 .grid{{display:grid;grid-template-columns:1.5fr 1fr;gap:14px;margin-bottom:14px}}
 .panel{{background:var(--panel);border:1px solid var(--border);border-radius:10px;padding:12px;position:relative;overflow:hidden}}
 .panel h3{{margin:0 0 8px 0;font-size:{font+1}px;color:#333}}
 .panel .sub{{font-size:{font-1}px;color:var(--muted);margin-bottom:6px}}
 .dead-list{{max-height:{height-80}px;overflow-y:auto;font-size:{font-1}px}}
 .dead-list .row{{padding:5px 8px;margin:2px 0;border-radius:4px;display:flex;justify-content:space-between;gap:8px;border:1px solid #f0f0f0}}
 .dead-list .row:hover{{background:#f5f5f5}}
 .dead-list .cat{{font-size:{font-2}px;padding:1px 6px;border-radius:3px;color:#fff;flex-shrink:0;font-weight:500}}
 .alive-list .row.top{{background:#fff8e6}}
 .miss-list{{max-height:280px;overflow-y:auto;font-size:{font-1}px;font-family:ui-monospace,"SF Mono",Menlo,monospace}}
 .miss-list .row{{padding:6px 10px;border-bottom:1px solid #f0f0f0}}
 .miss-list .prompt{{color:#333;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:680px}}
 .miss-list .gap{{color:#E45756;font-size:{font-2}px;margin-top:2px}}
 .tabs{{display:inline-flex;border:1px solid var(--border);border-radius:6px;overflow:hidden;margin-left:auto}}
 .tabs button{{border:0;background:transparent;padding:4px 12px;cursor:pointer;font-size:{font-1}px;color:#444}}
 .tabs button.active{{background:var(--accent);color:#fff}}
 details summary{{cursor:pointer;color:var(--accent);font-size:{font-1}px;margin-top:6px;user-select:none}}
 .legend-dot{{display:inline-block;width:9px;height:9px;border-radius:2px;margin-right:5px;vertical-align:middle}}
 .full{{grid-column:1/-1}}
 @media(max-width:1100px){{.grid{{grid-template-columns:1fr}}}}
</style></head>
<body>
<h1>md-trace v2 · 메타 라우팅 관측성</h1>
<div class="meta">{payload['meta']}</div>

<div class="health">
  <div class="kpi { 'good' if (payload['metrics']['sess_kw_rate'] or 0) >= 70 else 'warn' if payload['metrics']['sess_kw_rate'] is not None else '' }">
    <div class="v">{ f"{payload['metrics']['sess_kw_rate']:.0f}%" if payload['metrics']['sess_kw_rate'] is not None else "—" }</div>
    <div class="l">키워드 적중 (세션) {payload['metrics']['sess_kw_hit']}/{payload['metrics']['sess_kw_total']}<br><span style="font-size:0.85em;color:#888">발화 기준: {payload['metrics']['kw_hit']}/{payload['metrics']['kw_total']}</span></div>
  </div>
  <div class="kpi { 'good' if (payload['metrics']['ac_rate'] or 0) >= 70 else 'warn' if payload['metrics']['ac_rate'] is not None else '' }">
    <div class="v">{ f"{payload['metrics']['ac_rate']:.0f}%" if payload['metrics']['ac_rate'] is not None else "—" }</div>
    <div class="l">에이전트 호출 ({payload['metrics']['ac_hit']}/{payload['metrics']['ac_total']})</div>
  </div>
  <div class="kpi { 'good' if (payload['metrics']['al_rate'] or 0) >= 70 else 'warn' if payload['metrics']['al_rate'] is not None else '' }">
    <div class="v">{ f"{payload['metrics']['al_rate']:.0f}%" if payload['metrics']['al_rate'] is not None else "—" }</div>
    <div class="l">자동로딩 ({payload['metrics']['al_hit']}/{payload['metrics']['al_total']})</div>
  </div>
  <div class="kpi { 'warn' if payload['metrics']['dead_rate']>=50 else 'good' }">
    <div class="v">{payload['metrics']['dead_rate']:.0f}%</div>
    <div class="l">죽은 룰 비율 ({payload['dead_count']}/{payload['dead_count']+payload['alive_count']})</div>
  </div>
  <div class="kpi { 'warn' if payload['metrics']['no_exp_rate']>=30 else '' }">
    <div class="v">{payload['metrics']['no_exp_rate']:.0f}%</div>
    <div class="l">expected 미정의 룰 ({payload['metrics']['rules_no_expected']}/{payload['metrics']['total_rules']})</div>
  </div>
  <div class="kpi">
    <div class="v">{payload['turns_total']}</div>
    <div class="l">총 요청 · {payload['turns_with_reads']} Read · {payload['total_reads']} .md</div>
  </div>
</div>

<div class="controls">
  <label>높이 <input type="range" id="heightR" min="280" max="900" step="20" value="{height}"><span class="val" id="heightV">{height}</span>px</label>
  <label>폰트 <input type="range" id="fontR" min="10" max="18" step="1" value="{font}"><span class="val" id="fontV">{font}</span>px</label>
  <span style="color:#888">· 셀 클릭 시 드릴다운, 죽은 룰 패널 탭으로 활성/죽은 전환</span>
</div>

<div class="grid">
  <div class="panel">
    <h3>요청 카테고리 × .md 카테고리 (적중 분포)</h3>
    <div class="sub">셀 = 참조 횟수. 클릭하면 하단에 해당 셀의 요청-md 페어 표시</div>
    <div id="heatmap"></div>
  </div>
  <div class="panel">
    <h3 style="display:flex;align-items:center">룰 활용도
      <span class="tabs">
        <button id="tabAlive" class="active">활성</button>
        <button id="tabDead">죽은 룰</button>
      </span>
    </h3>
    <div class="sub" id="ruleSub">자주 참조된 .md TOP</div>
    <div class="dead-list alive-list" id="ruleList"></div>
  </div>
</div>

<div class="panel full" style="margin-bottom:14px">
  <h3>요청 카테고리 lane 타임라인 ({payload['days']}일)</h3>
  <div class="sub">x=날짜, y=카테고리, 셀 색=요청 수. 라우팅이 시간에 따라 어떻게 진화했는지</div>
  <div id="timeline"></div>
</div>

<div class="panel full" style="margin-bottom:14px">
  <h3 id="drillTitle">셀 드릴다운</h3>
  <div class="sub">위 Heatmap 셀을 클릭하세요</div>
  <div class="miss-list" id="drillList"><em style="color:#999">아직 선택된 셀이 없습니다.</em></div>
</div>

<div class="panel full">
  <h3>라우팅 갭 (기대 .md 가 있었지만 실제로 안 읽힌 요청)</h3>
  <div class="sub">{payload['miss_count']}건. CLAUDE.md 룰이 의도대로 동작 안 한 케이스 — 룰 강화/키워드 추가 후보</div>
  <div class="miss-list" id="missList"></div>
</div>

<script>
const HEAT = {json.dumps(payload['heatmap'], ensure_ascii=False)};
const ALIVE = {json.dumps(payload['alive'], ensure_ascii=False)};
const DEAD = {json.dumps(payload['dead'], ensure_ascii=False)};
const TIMELINE = {json.dumps(payload['timeline'], ensure_ascii=False)};
const MISSES = {json.dumps(payload['misses'], ensure_ascii=False)};
const CAT_COLORS = {json.dumps(CAT_COLORS, ensure_ascii=False)};
let currentFont = {font};
let currentHeight = {height};

function plotHeatmap() {{
  Plotly.newPlot("heatmap", [{{
    type: "heatmap",
    x: HEAT.x, y: HEAT.y, z: HEAT.z,
    text: HEAT.text,
    texttemplate: "%{{text}}",
    textfont: {{size: currentFont}},
    colorscale: [[0,"#f7f7f7"],[0.001,"#fff8e6"],[0.3,"#fcd07b"],[0.7,"#f1834c"],[1,"#c44a2c"]],
    showscale: false,
    hovertemplate: "<b>요청: %{{y}}</b> × <b>md: %{{x}}</b><br>%{{z}}건<extra></extra>",
  }}], {{
    margin: {{l:110, r:10, t:10, b:50}},
    height: currentHeight,
    font: {{size: currentFont}},
    xaxis: {{tickangle: -30}}, yaxis: {{automargin: true}},
  }}, {{displayModeBar:false, responsive:true}});
  document.getElementById("heatmap").on("plotly_click", (ev) => {{
    if (!ev.points || !ev.points[0]) return;
    const p = ev.points[0];
    showDrill(p.y, p.x, p.z);
  }});
}}

function plotTimeline() {{
  const z = TIMELINE.lanes.map(l => l.values);
  const y = TIMELINE.lanes.map(l => l.cat);
  Plotly.newPlot("timeline", [{{
    type:"heatmap",
    x: TIMELINE.dates, y: y, z: z,
    colorscale: [[0,"#f7f7f7"],[0.001,"#e6f0fa"],[0.5,"#7eb1da"],[1,"#1f5f9f"]],
    showscale: false,
    hovertemplate: "<b>%{{y}}</b><br>%{{x}}: %{{z}}건<extra></extra>",
  }}], {{
    margin: {{l:110, r:10, t:10, b:50}},
    height: Math.min(currentHeight, 32 * y.length + 90),
    font: {{size: currentFont}},
    xaxis: {{tickangle: -30}}, yaxis: {{automargin: true}},
  }}, {{displayModeBar:false, responsive:true}});
}}

function renderRules(mode) {{
  const list = mode === "alive" ? ALIVE : DEAD;
  const sub = mode === "alive"
    ? `자주 참조된 .md TOP (${{ALIVE.length}}개 활성)`
    : `한 번도 안 읽힌 .md (${{DEAD.length}}개 죽은 룰)`;
  document.getElementById("ruleSub").textContent = sub;
  const target = document.getElementById("ruleList");
  target.innerHTML = list.slice(0, 200).map((r, i) => {{
    const c = CAT_COLORS[r.cat] || "#999";
    const cnt = mode==="alive" ? `<span style="color:#666;font-variant-numeric:tabular-nums">${{r.count}}회</span>` : `<span style="color:#999;font-size:0.85em">0회</span>`;
    return `<div class="row ${{ mode==='alive' && i<3 ? 'top' : '' }}">
      <span><span class="cat" style="background:${{c}}">${{r.cat}}</span> ${{escapeHtml(r.md)}}</span>
      ${{cnt}}
    </div>`;
  }}).join("");
}}

function showDrill(reqCat, mdCat, count) {{
  const items = (HEAT.drilldown[reqCat] && HEAT.drilldown[reqCat][mdCat]) || [];
  document.getElementById("drillTitle").textContent =
    `드릴다운: 요청 [${{reqCat}}] × md [${{mdCat}}] — ${{count}}건`;
  const list = document.getElementById("drillList");
  if (!items.length) {{ list.innerHTML = "<em style='color:#999'>해당 셀에 데이터 없음</em>"; return; }}
  // 같은 (prompt, md) 페어 중복 제거 + 빈도 합산
  const map = new Map();
  for (const it of items) {{
    const k = it.prompt + "|" + it.md;
    if (!map.has(k)) map.set(k, {{...it, n:1}}); else map.get(k).n++;
  }}
  list.innerHTML = [...map.values()].slice(0, 200).map(it => `
    <div class="row">
      <div class="prompt"><b>${{(it.ts||"").slice(0,16).replace("T"," ")}}</b> ${{escapeHtml(it.prompt)}}</div>
      <div style="color:#4C78A8">→ ${{escapeHtml(it.md)}} ${{it.n>1?`<span style="color:#888">(×${{it.n}})</span>`:""}}</div>
    </div>
  `).join("");
}}

function renderMisses() {{
  const list = document.getElementById("missList");
  if (!MISSES.length) {{ list.innerHTML = "<em style='color:#999'>갭 없음 — 모든 룰이 정상 동작</em>"; return; }}
  list.innerHTML = MISSES.slice(0, 100).map(m => `
    <div class="row">
      <div class="prompt"><b>${{(m.ts||"").slice(0,16).replace("T"," ")}}</b> [${{(m.cats||[]).join(",")}}] ${{escapeHtml(m.prompt)}}</div>
      <div class="gap">기대: ${{(m.expected||[]).map(escapeHtml).join(", ")}} · 실제: ${{m.actual&&m.actual.length?m.actual.map(escapeHtml).join(", "):"<i>(.md Read 없음)</i>"}}</div>
    </div>
  `).join("");
}}

function escapeHtml(s) {{
  return String(s||"").replace(/[&<>"']/g, c => ({{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}})[c]);
}}

plotHeatmap();
plotTimeline();
renderRules("alive");
renderMisses();

document.getElementById("tabAlive").onclick = () => {{
  document.getElementById("tabAlive").classList.add("active");
  document.getElementById("tabDead").classList.remove("active");
  renderRules("alive");
}};
document.getElementById("tabDead").onclick = () => {{
  document.getElementById("tabDead").classList.add("active");
  document.getElementById("tabAlive").classList.remove("active");
  renderRules("dead");
}};

document.getElementById("heightR").addEventListener("input", e => {{
  currentHeight = +e.target.value;
  document.getElementById("heightV").textContent = currentHeight;
  plotHeatmap(); plotTimeline();
}});
document.getElementById("fontR").addEventListener("input", e => {{
  currentFont = +e.target.value;
  document.getElementById("fontV").textContent = currentFont;
  document.body.style.fontSize = currentFont + "px";
  plotHeatmap(); plotTimeline();
}});

window.addEventListener("resize", () => {{
  Plotly.Plots.resize("heatmap");
  Plotly.Plots.resize("timeline");
}});
</script>
</body></html>"""
    out_path.write_text(doc, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--scope", choices=["claude", "config", "all"], default="config",
                    help="config(기본)=workflows+skills+agents+memory+CLAUDE.md")
    ap.add_argument("--height", type=int, default=420)
    ap.add_argument("--font", type=int, default=12)
    ap.add_argument("--open", action="store_true")
    ap.add_argument("--out", default=str(OUT_DIR / "report-v2.html"))
    args = ap.parse_args()

    if not PROJECTS_DIR.exists():
        print(f"projects dir 없음: {PROJECTS_DIR}", file=sys.stderr)
        sys.exit(1)

    files, turns = collect(args.days, args.scope)
    if not turns:
        print(f"최근 {args.days}일 요청 없음.", file=sys.stderr)
        sys.exit(0)

    all_md = discover_all_md(args.scope)
    dead, alive = find_dead(all_md, turns)
    metrics = compute_metrics(turns, all_md)
    heat = build_heatmap(turns)
    tl = build_timeline(turns, args.days)

    turns_with_reads = [t for t in turns if t["reads"]]
    total_reads = sum(len(t["reads"]) for t in turns)

    payload = {
        "meta": (f"<b>{args.days}일</b> · scope=<b>{args.scope}</b> · 세션 "
                 f"{len({t['session'] for t in turns})} · 발견된 관리 .md {len(all_md)}개"),
        "days": args.days,
        "metrics": metrics,
        "dead_count": len(dead), "alive_count": len(alive),
        "total_reads": total_reads,
        "turns_with_reads": len(turns_with_reads),
        "turns_total": len(turns),
        "miss_count": len(metrics["misses"]),
        "heatmap": heat,
        "alive": alive,
        "dead": dead,
        "timeline": tl,
        "misses": metrics["misses"],
    }

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    render_html(payload, out_path, font=args.font, height=args.height)

    m = metrics
    def fmt(rate, hit, total):
        return f"{rate:.0f}% ({hit}/{total})" if rate is not None else f"— (0/{total})"
    print(f"리포트 생성: {out_path}")
    print(f"  키워드 적중(세션): {fmt(m['sess_kw_rate'], m['sess_kw_hit'], m['sess_kw_total'])}")
    print(f"  키워드 적중(발화): {fmt(m['kw_rate'], m['kw_hit'], m['kw_total'])}")
    print(f"  에이전트 호출 : {fmt(m['ac_rate'], m['ac_hit'], m['ac_total'])}")
    print(f"  자동로딩      : {fmt(m['al_rate'], m['al_hit'], m['al_total'])}")
    print(f"  죽은 룰 비율  : {m['dead_rate']:.0f}% ({len(dead)}/{len(all_md)}) · 활성 {len(alive)}")
    print(f"  expected 미정의 룰: {m['no_exp_rate']:.0f}% ({m['rules_no_expected']}/{m['total_rules']})")
    print(f"  총 요청: {len(turns)} (.md 끌어온 요청 {len(turns_with_reads)})")
    print(f"  TOP 5 활성:")
    for r in alive[:5]:
        print(f"    {r['count']:4d}  [{r['cat']:9s}] {r['md']}")
    if dead:
        print(f"  TOP 5 죽은 룰:")
        for r in dead[:5]:
            print(f"        [{r['cat']:9s}] {r['md']}")

    if args.open:
        webbrowser.open(f"file://{out_path}")


if __name__ == "__main__":
    main()
