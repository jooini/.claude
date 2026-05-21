#!/usr/bin/env python3
"""md-trace: 사용자 요청별로 어떤 .md를 Read 했는지 추적해서 Sankey HTML로 시각화한다.

데이터 소스: ~/.claude/projects/**/*.jsonl (Claude Code transcript)
출력: ~/.claude/cache/md-trace/report.html (Plotly CDN 단일 파일)
"""
import argparse
import html
import json
import os
import re
import sys
import time
import webbrowser
from collections import Counter, defaultdict
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
]


def clean_prompt(text: str) -> str:
    for pat in SYSTEM_PATTERNS:
        text = pat.sub("", text)
    return text.strip()


def short_label(text: str, n: int = 60) -> str:
    text = " ".join(text.split())
    if len(text) <= n:
        return text or "(빈 입력)"
    return text[: n - 1] + "…"


def relpath_md(file_path: str) -> str:
    p = Path(file_path)
    try:
        return str(p.relative_to(CLAUDE_ROOT))
    except ValueError:
        return str(p)


def categorize(rel: str) -> str:
    if rel.startswith("workflows/"):
        return "workflows"
    if rel.startswith("skills/"):
        return "skills"
    if rel.startswith("agents/"):
        return "agents"
    if "memory/" in rel and rel.startswith("projects/"):
        return "memory"
    if rel.startswith("plugins/"):
        return "plugins"
    if rel == "CLAUDE.md" or rel.endswith("/CLAUDE.md"):
        return "CLAUDE.md"
    if rel.startswith("/"):
        return "project"
    return "other"


def is_in_scope(rel: str, scope: str) -> bool:
    if scope == "all":
        return True
    if scope == "claude":
        return not rel.startswith("/")
    if scope == "config":
        return categorize(rel) in {"workflows", "skills", "agents", "memory", "CLAUDE.md"}
    return True


def iter_user_turns(jsonl_path: Path):
    """jsonl 파일 한 개에서 (user_prompt, ts, [md_path, ...], prompt_id) 리스트를 yield."""
    current_prompt = None
    current_ts = None
    current_pid = None
    current_reads: list[str] = []

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
                text = ""
                if isinstance(content, str):
                    text = content
                elif isinstance(content, list):
                    parts = []
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text":
                            parts.append(c.get("text", ""))
                        elif isinstance(c, dict) and c.get("type") == "tool_result":
                            continue
                    text = "\n".join(parts)
                cleaned = clean_prompt(text)
                if not cleaned:
                    continue
                if current_prompt is not None:
                    yield (current_prompt, current_ts, list(current_reads), current_pid)
                current_prompt = cleaned
                current_ts = rec.get("timestamp", "")
                current_pid = rec.get("promptId") or rec.get("uuid") or ""
                current_reads = []
            elif rtype == "assistant" and current_prompt is not None:
                msg = rec.get("message") or {}
                content = msg.get("content")
                if isinstance(content, list):
                    for c in content:
                        if (
                            isinstance(c, dict)
                            and c.get("type") == "tool_use"
                            and c.get("name") == "Read"
                        ):
                            fp = (c.get("input") or {}).get("file_path")
                            if isinstance(fp, str) and fp.endswith(".md"):
                                current_reads.append(fp)
        if current_prompt is not None:
            yield (current_prompt, current_ts, list(current_reads), current_pid)


def collect_subagent_index() -> dict:
    """subagent jsonl을 promptId → [{agent, files}] 인덱스로 구축.

    각 subagent 디렉토리: ~/.claude/projects/<proj>/<session>/subagents/agent-<id>.jsonl
    - .meta.json에서 agentType/description 추출
    - jsonl의 promptId가 부모 turn_id와 동일 → 조인 키
    - tool_use(Read/Grep/Glob) 의 file_path 수집
    """
    index: dict[str, list[dict]] = defaultdict(list)
    for agent_jsonl in PROJECTS_DIR.glob("**/subagents/agent-*.jsonl"):
        if agent_jsonl.suffix != ".jsonl":
            continue
        meta_path = agent_jsonl.with_suffix(".meta.json")
        agent_type = "unknown"
        description = ""
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
                agent_type = meta.get("agentType") or "unknown"
                description = meta.get("description") or ""
            except (json.JSONDecodeError, OSError):
                pass

        prompt_id = ""
        files: list[str] = []
        try:
            with agent_jsonl.open("r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        rec = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if not prompt_id:
                        pid = rec.get("promptId")
                        if pid:
                            prompt_id = pid
                    msg = rec.get("message") or {}
                    content = msg.get("content")
                    if isinstance(content, list):
                        for c in content:
                            if (
                                isinstance(c, dict)
                                and c.get("type") == "tool_use"
                                and c.get("name") in ("Read", "Grep", "Glob")
                            ):
                                fp = (c.get("input") or {}).get("file_path") or (
                                    c.get("input") or {}
                                ).get("path")
                                if isinstance(fp, str):
                                    files.append(fp)
        except OSError:
            continue

        if not prompt_id:
            continue
        index[prompt_id].append(
            {
                "agent": agent_type,
                "description": description,
                "files": files,
                "agent_id": agent_jsonl.stem.replace("agent-", "")[:8],
            }
        )
    return index


def collect(days: int, scope: str):
    cutoff = time.time() - days * 86400
    files = []
    for p in PROJECTS_DIR.rglob("*.jsonl"):
        # subagent jsonl 은 별도 인덱스로 처리
        if "subagents" in p.parts:
            continue
        try:
            if p.stat().st_mtime >= cutoff:
                files.append(p)
        except OSError:
            continue

    subagent_index = collect_subagent_index()

    turns = []
    for p in sorted(files, key=lambda x: x.stat().st_mtime):
        for prompt, ts, reads, pid in iter_user_turns(p):
            md_reads = [relpath_md(r) for r in reads]
            md_reads = [m for m in md_reads if is_in_scope(m, scope)]
            agents = []
            for a in subagent_index.get(pid, []):
                agent_files = [relpath_md(f) for f in a["files"]]
                agent_files = [f for f in agent_files if is_in_scope(f, scope)]
                agents.append(
                    {
                        "agent": a["agent"],
                        "description": a["description"],
                        "files": agent_files,
                        "agent_id": a["agent_id"],
                    }
                )
            turns.append(
                {
                    "prompt": prompt,
                    "label": short_label(prompt),
                    "ts": ts,
                    "session": p.stem,
                    "project": p.parent.name,
                    "prompt_id": pid,
                    "reads": md_reads,
                    "agents": agents,
                }
            )
    return files, turns


def build_sankey(turns, top_prompts: int):
    """4컬럼 Sankey: prompt → md(부모 Read) + prompt → agent → file(에이전트 Read).

    md 와 file 은 같은 카테고리 색으로 표시. agent 노드는 보라 계열.
    """
    pair_counts: Counter = Counter()  # (prompt_key, md)
    md_total: Counter = Counter()
    prompt_total: Counter = Counter()
    prompt_meta: dict[str, dict] = {}

    # 부모 Read 집계
    for i, t in enumerate(turns):
        if not t["reads"] and not t.get("agents"):
            continue
        prompt_key = f"{t['ts']}__{i}"
        prompt_meta[prompt_key] = t
        for md in t["reads"]:
            pair_counts[(prompt_key, md)] += 1
            md_total[md] += 1
            prompt_total[prompt_key] += 1
        for a in t.get("agents", []):
            prompt_total[prompt_key] += 1 + len(a["files"])

    kept_prompts = {k for k, _ in prompt_total.most_common(top_prompts)}

    # prompt → md 집계
    agg_prompt_md: Counter = Counter()
    for (pk, md), cnt in pair_counts.items():
        node_label = (
            f"[{prompt_meta[pk]['ts'][5:16]}] {prompt_meta[pk]['label']}"
            if pk in kept_prompts
            else "기타 요청 (합산)"
        )
        agg_prompt_md[(node_label, md, pk if pk in kept_prompts else "__other__")] += cnt

    # prompt → agent, agent → file 집계
    # agent 노드 key: (agent_type, agent_id_short)  — 같은 종류여도 인스턴스 구분
    agent_total: Counter = Counter()
    agent_files_total: Counter = Counter()
    agg_prompt_agent: Counter = Counter()  # (prompt_label, agent_label, pk)
    agg_agent_file: Counter = Counter()  # (agent_label, file)
    agent_meta: dict[str, dict] = {}

    for pk, t in prompt_meta.items():
        prompt_label = (
            f"[{t['ts'][5:16]}] {t['label']}"
            if pk in kept_prompts
            else "기타 요청 (합산)"
        )
        pk_eff = pk if pk in kept_prompts else "__other__"
        for a in t.get("agents", []):
            agent_label = f"🤖 {a['agent']}"
            if a["description"]:
                agent_meta[agent_label] = {
                    "description": a["description"],
                    "agent_id": a["agent_id"],
                }
            agg_prompt_agent[(prompt_label, agent_label, pk_eff)] += 1
            agent_total[agent_label] += 1
            for f in a["files"]:
                agg_agent_file[(agent_label, f)] += 1
                agent_files_total[f] += 1

    # 노드 순서: prompt → md → agent → file
    prompt_nodes: list[str] = []
    prompt_index: dict[str, int] = {}
    md_nodes: list[str] = []
    md_index: dict[str, int] = {}
    agent_nodes: list[str] = []
    agent_index: dict[str, int] = {}
    file_nodes: list[str] = []
    file_index: dict[str, int] = {}

    for (pnode, md, _pk), _cnt in sorted(
        agg_prompt_md.items(), key=lambda x: (-x[1], x[0][0])
    ):
        if pnode not in prompt_index:
            prompt_index[pnode] = len(prompt_nodes)
            prompt_nodes.append(pnode)
        if md not in md_index:
            md_index[md] = len(md_nodes)
            md_nodes.append(md)

    for (pnode, anode, _pk), _cnt in sorted(
        agg_prompt_agent.items(), key=lambda x: (-x[1], x[0][1])
    ):
        if pnode not in prompt_index:
            prompt_index[pnode] = len(prompt_nodes)
            prompt_nodes.append(pnode)
        if anode not in agent_index:
            agent_index[anode] = len(agent_nodes)
            agent_nodes.append(anode)

    for (anode, f), _cnt in sorted(
        agg_agent_file.items(), key=lambda x: (-x[1], x[0][1])
    ):
        if anode not in agent_index:
            agent_index[anode] = len(agent_nodes)
            agent_nodes.append(anode)
        if f not in file_index:
            file_index[f] = len(file_nodes)
            file_nodes.append(f)

    cat_colors = {
        "workflows": "#F58518",
        "skills": "#54A24B",
        "agents": "#B279A2",
        "memory": "#EECA3B",
        "plugins": "#9D755D",
        "CLAUDE.md": "#E45756",
        "project": "#72B7B2",
        "other": "#BAB0AC",
    }
    AGENT_COLOR = "#9467BD"
    PROMPT_COLOR = "#4C78A8"

    n_prompt = len(prompt_nodes)
    n_md = len(md_nodes)
    n_agent = len(agent_nodes)
    base_md = n_prompt
    base_agent = n_prompt + n_md
    base_file = n_prompt + n_md + n_agent

    node_labels = prompt_nodes + md_nodes + agent_nodes + file_nodes
    node_colors = (
        [PROMPT_COLOR] * n_prompt
        + [cat_colors.get(categorize(m), "#BAB0AC") for m in md_nodes]
        + [AGENT_COLOR] * n_agent
        + [cat_colors.get(categorize(f), "#BAB0AC") for f in file_nodes]
    )

    node_hover = []
    for pn in prompt_nodes:
        if pn == "기타 요청 (합산)":
            node_hover.append("나머지 요청 합산")
        else:
            ts_label = pn.split("] ", 1)[0][1:]
            node_hover.append(f"{ts_label}<br>{html.escape(pn.split('] ',1)[-1])}")
    for md in md_nodes:
        node_hover.append(
            f"{html.escape(md)}<br>분류: {categorize(md)}<br>총 {md_total[md]}회 부모 Read"
        )
    for an in agent_nodes:
        meta = agent_meta.get(an, {})
        desc = html.escape(meta.get("description", "") or "")
        agent_read_total = sum(
            cnt for (a, _f), cnt in agg_agent_file.items() if a == an
        )
        node_hover.append(
            f"<b>{html.escape(an)}</b><br>"
            f"디스패치 {agent_total[an]}회 · 에이전트 Read {agent_read_total}건<br>"
            f"{desc}"
        )
    for f in file_nodes:
        node_hover.append(
            f"{html.escape(f)}<br>분류: {categorize(f)}<br>"
            f"에이전트 Read 총 {agent_files_total[f]}회"
        )

    sources, targets, values, hovers = [], [], [], []

    # prompt → md
    for (pnode, md, pk), cnt in agg_prompt_md.items():
        sources.append(prompt_index[pnode])
        targets.append(base_md + md_index[md])
        values.append(cnt)
        if pk == "__other__":
            hovers.append(f"기타 요청 → {html.escape(md)}<br>{cnt}회 (부모 Read)")
        else:
            full = prompt_meta[pk]["prompt"][:200].replace("\n", " ")
            hovers.append(
                f"<b>요청</b>: {html.escape(full)}<br>"
                f"<b>md (부모 Read)</b>: {html.escape(md)}<br>"
                f"<b>세션</b>: {prompt_meta[pk]['session'][:8]}"
            )

    # prompt → agent
    for (pnode, anode, pk), cnt in agg_prompt_agent.items():
        sources.append(prompt_index[pnode])
        targets.append(base_agent + agent_index[anode])
        values.append(cnt)
        if pk == "__other__":
            hovers.append(
                f"기타 요청 → {html.escape(anode)}<br>{cnt}회 디스패치"
            )
        else:
            full = prompt_meta[pk]["prompt"][:200].replace("\n", " ")
            hovers.append(
                f"<b>요청</b>: {html.escape(full)}<br>"
                f"<b>디스패치</b>: {html.escape(anode)}"
            )

    # agent → file
    for (anode, f), cnt in agg_agent_file.items():
        sources.append(base_agent + agent_index[anode])
        targets.append(base_file + file_index[f])
        values.append(cnt)
        hovers.append(
            f"<b>{html.escape(anode)}</b>가 Read<br>"
            f"<b>file</b>: {html.escape(f)}<br>{cnt}회"
        )

    # agent 만 디스패치되고 자체 Read 가 0인 경우 강조용 정보
    agents_no_read = [
        an
        for an in agent_nodes
        if not any(a == an for (a, _f) in agg_agent_file)
    ]

    return {
        "labels": node_labels,
        "colors": node_colors,
        "node_hover": node_hover,
        "sources": sources,
        "targets": targets,
        "values": values,
        "link_hover": hovers,
        "md_total": md_total,
        "n_prompts": n_prompt,
        "n_md": n_md,
        "n_agents": n_agent,
        "n_files": len(file_nodes),
        "agents_no_read": agents_no_read,
    }


def render_html(
    payload, summary, out_path: Path, height: int = 720, font: int = 11, layout: str = "side"
):
    cat_colors = {
        "workflows": "#F58518",
        "skills": "#54A24B",
        "agents": "#B279A2",
        "memory": "#EECA3B",
        "plugins": "#9D755D",
        "CLAUDE.md": "#E45756",
        "project": "#72B7B2",
        "other": "#BAB0AC",
    }
    md_top = payload["md_total"].most_common(20)
    bar_x = [c for _, c in md_top]
    bar_y = [m for m, _ in md_top]
    bar_colors = [cat_colors.get(categorize(m), "#BAB0AC") for m in bar_y]

    sankey_data = {
        "type": "sankey",
        "arrangement": "snap",
        "node": {
            "label": payload["labels"],
            "color": payload["colors"],
            "customdata": payload["node_hover"],
            "hovertemplate": "%{customdata}<extra></extra>",
            "pad": 14,
            "thickness": 16,
        },
        "link": {
            "source": payload["sources"],
            "target": payload["targets"],
            "value": payload["values"],
            "customdata": payload["link_hover"],
            "hovertemplate": "%{customdata}<extra></extra>",
        },
    }
    bar_data = {
        "type": "bar",
        "orientation": "h",
        "x": bar_x,
        "y": bar_y,
        "marker": {"color": bar_colors},
        "hovertemplate": "%{y}: %{x}회<extra></extra>",
    }

    legend_items = "".join(
        f'<span style="display:inline-block;width:10px;height:10px;background:{c};border-radius:2px;margin:0 4px 0 12px;vertical-align:middle"></span>{k}'
        for k, c in cat_colors.items()
    )
    agents_no_read = payload.get("agents_no_read") or []
    no_read_html = ""
    if agents_no_read:
        chips = " ".join(
            f'<span style="display:inline-block;padding:2px 8px;margin:2px;background:#fee;color:#a33;'
            f'border:1px solid #f5b5b5;border-radius:10px;font-size:11px">{html.escape(a)}</span>'
            for a in agents_no_read[:20]
        )
        no_read_html = (
            f'<div style="margin-top:6px;font-size:12px;color:#a33">'
            f'⚠ 디스패치됐지만 자체 Read 0건 (knowledge 미열람): {chips}</div>'
        )

    summary_html = (
        f"<b>{summary['days']}일</b> · scope=<b>{summary['scope']}</b> · "
        f"세션 {summary['sessions']}개 · 요청 {summary['prompts']}건 · "
        f"md {payload['n_md']}개 · 에이전트 {payload.get('n_agents', 0)}개 · "
        f"에이전트 Read 파일 {payload.get('n_files', 0)}개 · "
        f"엣지 {sum(payload['values'])}건"
        f'<div style="margin-top:6px;font-size:11px;color:#666">{legend_items}</div>'
        f"{no_read_html}"
    )

    initial_grid = (
        "grid-template-columns:2fr 1fr"
        if layout == "side"
        else "grid-template-columns:1fr"
    )

    doc = f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<title>md-trace report</title>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<style>
 body{{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;margin:24px;background:#fafafa;color:#222}}
 h1{{margin:0 0 4px 0;font-size:20px}}
 .summary{{color:#555;margin-bottom:12px;font-size:13px}}
 .controls{{display:flex;flex-wrap:wrap;gap:14px;align-items:center;background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:10px 14px;margin-bottom:14px;font-size:12px;color:#333}}
 .controls label{{display:flex;align-items:center;gap:6px}}
 .controls input[type=range]{{width:140px}}
 .controls .val{{display:inline-block;min-width:42px;text-align:right;color:#666;font-variant-numeric:tabular-nums}}
 .controls button{{border:1px solid #d0d0d0;background:#fafafa;border-radius:6px;padding:4px 10px;cursor:pointer;font-size:12px}}
 .controls button:hover{{background:#f0f0f0}}
 .controls button.active{{background:#4C78A8;color:#fff;border-color:#4C78A8}}
 .panel{{background:#fff;border:1px solid #e5e5e5;border-radius:8px;padding:12px;margin-bottom:18px;position:relative}}
 .grid{{display:grid;{initial_grid};gap:18px}}
 .resizer{{position:absolute;left:0;right:0;bottom:-3px;height:6px;cursor:ns-resize;background:transparent}}
 .resizer:hover{{background:rgba(76,120,168,0.18)}}
</style></head>
<body>
<h1>md-trace · 요청 → 참조한 .md</h1>
<div class="summary">{summary_html}</div>
<div class="controls">
  <label>높이 <input type="range" id="heightR" min="320" max="1600" step="20" value="{height}"><span class="val" id="heightV">{height}</span>px</label>
  <label>폰트 <input type="range" id="fontR" min="8" max="20" step="1" value="{font}"><span class="val" id="fontV">{font}</span>px</label>
  <label>레이아웃
    <button id="layoutSide" class="{ 'active' if layout=='side' else '' }">좌우</button>
    <button id="layoutStack" class="{ 'active' if layout=='stack' else '' }">세로</button>
  </label>
  <label>막대그래프
    <button id="barToggle" class="active">표시</button>
  </label>
  <span style="color:#888">· 패널 하단을 드래그해서 개별 높이 조정</span>
</div>
<div class="grid" id="grid">
  <div class="panel" id="sankeyPanel"><div id="sankey" style="height:{height}px"></div><div class="resizer" data-target="sankey"></div></div>
  <div class="panel" id="barPanel"><div id="bar" style="height:{height}px"></div><div class="resizer" data-target="bar"></div></div>
</div>
<script>
const sankeyData = {json.dumps(sankey_data, ensure_ascii=False)};
const barData = {json.dumps(bar_data, ensure_ascii=False)};
let currentFont = {font};

function plot(id, data, layout) {{
  Plotly.react(id, [data], layout, {{displayModeBar:false, responsive:true}});
}}

function sankeyLayout() {{
  return {{margin:{{l:10,r:10,t:10,b:10}}, font:{{size:currentFont}}, autosize:true}};
}}
function barLayout() {{
  return {{
    margin:{{l:240,r:20,t:30,b:30}},
    title:{{text:"TOP 20 자주 참조된 .md", font:{{size:currentFont+2}}}},
    font:{{size:currentFont}}, yaxis:{{autorange:"reversed"}}, autosize:true
  }};
}}

plot("sankey", sankeyData, sankeyLayout());
plot("bar", barData, barLayout());

document.getElementById("heightR").addEventListener("input", (e) => {{
  const h = +e.target.value;
  document.getElementById("heightV").textContent = h;
  document.getElementById("sankey").style.height = h+"px";
  document.getElementById("bar").style.height = h+"px";
  Plotly.Plots.resize("sankey");
  Plotly.Plots.resize("bar");
}});

document.getElementById("fontR").addEventListener("input", (e) => {{
  currentFont = +e.target.value;
  document.getElementById("fontV").textContent = currentFont;
  Plotly.relayout("sankey", {{"font.size":currentFont}});
  Plotly.relayout("bar", {{"font.size":currentFont, "title.font.size":currentFont+2}});
}});

const sideBtn = document.getElementById("layoutSide");
const stackBtn = document.getElementById("layoutStack");
function setLayout(mode) {{
  const grid = document.getElementById("grid");
  grid.style.gridTemplateColumns = mode==="side" ? "2fr 1fr" : "1fr";
  sideBtn.classList.toggle("active", mode==="side");
  stackBtn.classList.toggle("active", mode==="stack");
  Plotly.Plots.resize("sankey");
  Plotly.Plots.resize("bar");
}}
sideBtn.addEventListener("click", () => setLayout("side"));
stackBtn.addEventListener("click", () => setLayout("stack"));

const barToggle = document.getElementById("barToggle");
barToggle.addEventListener("click", () => {{
  const p = document.getElementById("barPanel");
  const visible = p.style.display !== "none";
  p.style.display = visible ? "none" : "";
  barToggle.classList.toggle("active", !visible);
  barToggle.textContent = visible ? "표시" : "숨김";
  if (!visible) Plotly.Plots.resize("bar");
  Plotly.Plots.resize("sankey");
}});

document.querySelectorAll(".resizer").forEach(r => {{
  r.addEventListener("mousedown", (ev) => {{
    ev.preventDefault();
    const target = document.getElementById(r.dataset.target);
    const startY = ev.clientY;
    const startH = target.getBoundingClientRect().height;
    const move = (e) => {{
      const h = Math.max(200, startH + (e.clientY - startY));
      target.style.height = h+"px";
      Plotly.Plots.resize(target.id);
    }};
    const up = () => {{
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    }};
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  }});
}});

window.addEventListener("resize", () => {{
  Plotly.Plots.resize("sankey");
  Plotly.Plots.resize("bar");
}});
</script>
</body></html>"""
    out_path.write_text(doc, encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--top", type=int, default=30, help="Sankey 좌측에 표시할 prompt 수")
    ap.add_argument(
        "--scope",
        choices=["claude", "config", "all"],
        default="claude",
        help="claude=~/.claude만, config=workflows+skills+agents+memory+CLAUDE.md, all=모든 .md",
    )
    ap.add_argument("--height", type=int, default=720, help="차트 초기 높이 px")
    ap.add_argument("--font", type=int, default=11, help="차트 폰트 크기 px")
    ap.add_argument(
        "--layout",
        choices=["side", "stack"],
        default="side",
        help="side=좌우 2:1, stack=세로 적층",
    )
    ap.add_argument("--open", action="store_true", help="생성 후 브라우저로 열기")
    ap.add_argument("--out", default=str(OUT_DIR / "report.html"))
    args = ap.parse_args()

    if not PROJECTS_DIR.exists():
        print(f"projects dir 없음: {PROJECTS_DIR}", file=sys.stderr)
        sys.exit(1)

    files, turns = collect(args.days, args.scope)
    turns_with_signal = [t for t in turns if t["reads"] or t.get("agents")]
    if not turns_with_signal:
        print(
            f"최근 {args.days}일 내 (scope={args.scope}) .md Read 또는 agent 디스패치가 포함된 요청이 없음.",
            file=sys.stderr,
        )
        sys.exit(0)
    turns_with_reads = turns_with_signal

    payload = build_sankey(turns_with_reads, top_prompts=args.top)
    summary = {
        "days": args.days,
        "scope": args.scope,
        "sessions": len({t["session"] for t in turns_with_reads}),
        "prompts": len(turns_with_reads),
    }
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    render_html(
        payload,
        summary,
        out_path,
        height=args.height,
        font=args.font,
        layout=args.layout,
    )

    print(f"리포트 생성: {out_path}")
    print(
        f"  세션 {summary['sessions']} / 요청 {summary['prompts']} / "
        f"md {payload['n_md']} / 에이전트 {payload.get('n_agents',0)} / "
        f"에이전트 Read 파일 {payload.get('n_files',0)} / 엣지 {sum(payload['values'])}건"
    )
    print("  TOP 5 md (부모 Read):")
    for md, cnt in payload["md_total"].most_common(5):
        print(f"    {cnt:4d}  {md}")
    no_read = payload.get("agents_no_read") or []
    if no_read:
        print(f"  ⚠ knowledge 미열람 에이전트 {len(no_read)}건:")
        for an in no_read[:10]:
            print(f"    - {an}")

    if args.open:
        webbrowser.open(f"file://{out_path}")


if __name__ == "__main__":
    main()
