"""dashboard 데이터 빌더 — JSONL 읽기, chain 그래프 생성."""
import json
from datetime import datetime
from pathlib import Path

from .config import TRACE_DIR, LIVE_DIR


def get_today_file():
    return TRACE_DIR / f"{datetime.now().strftime('%Y-%m-%d')}.jsonl"

def tail_lines(n=200):
    """최근 N개 라인 반환"""
    f = get_today_file()
    if not f.exists():
        return []
    with f.open() as fh:
        lines = fh.readlines()
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except Exception:
            pass
    return out

def get_today_md_live_file():
    return LIVE_DIR / f"{datetime.now().strftime('%Y-%m-%d')}.jsonl"

def tail_md_live_lines(n=200):
    """md-live JSONL 최근 N개 라인 반환"""
    f = get_today_md_live_file()
    if not f.exists():
        return []
    with f.open() as fh:
        lines = fh.readlines()
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except Exception:
            pass
    return out

def _read_jsonl(path):
    if not path.exists():
        return []
    out = []
    with path.open() as fh:
        for ln in fh:
            ln = ln.strip()
            if not ln:
                continue
            try:
                out.append(json.loads(ln))
            except Exception:
                pass
    return out

def build_chains(max_turns=30):
    """
    md-live + tool-trace + turns 3개 JSONL 을 turn_id 로 조인하여 chain 그래프 데이터 생성.

    Returns:
      {
        "turns": [
          {
            "turn_id": "60a265d8...",
            "session": "7b153084",
            "ts_utc": "2026-05-09T10:36:20Z",
            "prompt_preview": "...",
            "reads": [{"ts_utc","category","file"}, ...],   # 시간순
            "tools": [{"ts_utc","tool","target"}, ...],     # 시간순
          }, ...
        ],
        "co_occurrence": [
          # 같은 turn 안에서 함께 등장한 (file_or_tool, file_or_tool, count)
          {"a": "...", "b": "...", "count": 3, "a_kind": "md", "b_kind": "tool"}
        ],
        "sankey": {
          # 발화 카테고리(추정) → md 카테고리 → tool name
          "nodes": [...],
          "links": [{"source": idx, "target": idx, "value": n}]
        }
      }
    """
    # 모든 날짜의 md / tool-trace / agent-trace 파일 읽기 (백필 데이터 포함)
    turns_path = LIVE_DIR / "turns.jsonl"
    md_rows = []
    tool_rows = []
    agent_rows = []
    for f in LIVE_DIR.glob("*.jsonl"):
        name = f.name
        if name in ("turns.jsonl", "agent-reads.jsonl"):
            continue
        if name.startswith("agent-trace-"):
            agent_rows.extend(_read_jsonl(f))
        elif name.startswith("tool-trace-"):
            tool_rows.extend(_read_jsonl(f))
        elif name[:4].isdigit() and name.endswith(".jsonl"):
            # YYYY-MM-DD.jsonl
            md_rows.extend(_read_jsonl(f))
    turn_rows = _read_jsonl(turns_path)
    agent_reads_rows = _read_jsonl(LIVE_DIR / "agent-reads.jsonl")

    # turn_id 가 비어있는 (P1 이전 KST-only 데이터) 줄은 스킵 — 그래프 노드로 못씀
    turns_by_id = {}
    for t in turn_rows[-max_turns * 3:]:  # 여유 있게
        tid = t.get("turn_id")
        if not tid:
            continue
        turns_by_id[tid] = {
            "turn_id": tid,
            "session": t.get("session", ""),
            "ts_utc": t.get("ts_utc", ""),
            "prompt_preview": t.get("prompt_preview", ""),
            "reads": [],
            "tools": [],
            "agents": [],
        }

    for r in md_rows:
        tid = r.get("turn_id")
        if not tid or tid not in turns_by_id:
            continue
        turns_by_id[tid]["reads"].append({
            "ts_utc": r.get("ts_utc", ""),
            "category": r.get("category", "other"),
            "file": r.get("file", ""),
        })
    # agent_reads 를 (session, agent_type) + first_ts 키로 그룹화 — agent 노드와 매칭용
    # key = (session, agent_type, first_ts_utc)
    ar_by_key = {}
    for r in agent_reads_rows:
        key = (r.get("session", ""), r.get("agent_type", ""), r.get("agent_first_ts_utc", ""))
        ar_by_key.setdefault(key, []).append({
            "ts_utc": r.get("ts_utc", ""),
            "category": r.get("category", "other"),
            "file": r.get("file", ""),
        })
    # ts_utc 정렬
    for v in ar_by_key.values():
        v.sort(key=lambda x: x.get("ts_utc", ""))

    def _ts_to_epoch(ts):
        if not ts: return 0
        try:
            from datetime import datetime
            return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").timestamp()
        except Exception:
            return 0

    for r in agent_rows:
        tid = r.get("turn_id")
        if not tid or tid not in turns_by_id:
            continue
        # subagent reads 매칭 — (session, agent_type) 같고 first_ts_utc 가 agent_call ts 와 가까운 (±5분)
        agent_ts = r.get("ts_utc", "")
        sess = turns_by_id[tid].get("session", "")
        agent_type = r.get("agent", "general-purpose")
        matched_reads = []
        agent_epoch = _ts_to_epoch(agent_ts)
        for (s, at, fts), rds in ar_by_key.items():
            if s != sess or at != agent_type:
                continue
            fts_epoch = _ts_to_epoch(fts)
            # 5분 이내 차이만 매칭
            if abs(fts_epoch - agent_epoch) <= 300:
                matched_reads.extend(rds)
        # 시간순
        matched_reads.sort(key=lambda x: x.get("ts_utc", ""))
        turns_by_id[tid]["agents"].append({
            "ts_utc": agent_ts,
            "agent": agent_type,
            "description": r.get("description", ""),
            "reads": matched_reads,
        })
    for r in tool_rows:
        tid = r.get("turn_id")
        if not tid or tid not in turns_by_id:
            continue
        turns_by_id[tid]["tools"].append({
            "ts_utc": r.get("ts_utc", ""),
            "tool": r.get("tool", ""),
            "target": r.get("target", ""),
        })

    # 시간순 정렬 + 연속 같은 (tool, target) 합치기
    def _collapse_consecutive(items, key_fn):
        out = []
        for it in items:
            k = key_fn(it)
            if out and key_fn(out[-1]) == k:
                out[-1]["count"] = out[-1].get("count", 1) + 1
                out[-1]["ts_utc_last"] = it.get("ts_utc", "")
            else:
                it = dict(it)
                it["count"] = 1
                it["ts_utc_last"] = it.get("ts_utc", "")
                out.append(it)
        return out

    def _tool_collapse_key(x):
        # Bash 는 명령어 첫 단어만 (예: "git diff" / "git status" → "Bash:git")
        # Edit/Write 는 file_path 그대로
        tool = x.get("tool", "")
        target = x.get("target", "") or ""
        if tool == "Bash":
            first = target.strip().split()
            head = first[0] if first else ""
            return (tool, head)
        return (tool, target[:80])

    for t in turns_by_id.values():
        t["reads"].sort(key=lambda x: x.get("ts_utc", ""))
        t["tools"].sort(key=lambda x: x.get("ts_utc", ""))
        t["agents"].sort(key=lambda x: x.get("ts_utc", ""))
        # 연속 같은 .md Read 합치기
        t["reads"] = _collapse_consecutive(t["reads"], lambda x: x.get("file", ""))
        # 연속 같은 (tool, target) 합치기 — Bash 는 첫 단어 기준
        t["tools"] = _collapse_consecutive(t["tools"], _tool_collapse_key)
        # 연속 같은 agent 합치기
        t["agents"] = _collapse_consecutive(t["agents"], lambda x: x.get("agent", ""))

    # 빈 turn 제외 — reads/tools/agents 모두 비어있으면 클라이언트가 어차피 필터링 (line 1115)
    non_empty = [
        t for t in turns_by_id.values()
        if t["reads"] or t["tools"] or t["agents"]
    ]
    # 최근 max_turns 개만 ts_utc 역순으로
    turns_list = sorted(non_empty, key=lambda x: x.get("ts_utc", ""), reverse=True)[:max_turns]
    # 화면 표시는 다시 시간 정순
    turns_list.sort(key=lambda x: x.get("ts_utc", ""))

    # 페이로드 다이어트 — 클라이언트 미사용 필드 제거 + 긴 문자열 컷
    PROMPT_MAX = 200
    TARGET_MAX = 500   # Bash 명령 등 tool.target — cytoscape text-max-width 가 어차피 자르므로 시각적 무해
    DESC_MAX = 120     # agent.description — UI 에서 80자 slice 함
    for t in turns_list:
        pp = t.get("prompt_preview", "") or ""
        if len(pp) > PROMPT_MAX:
            t["prompt_preview"] = pp[:PROMPT_MAX] + "..."
        for r in t["reads"]:
            r.pop("ts_utc_last", None)
        for r in t["tools"]:
            r.pop("ts_utc_last", None)
            tgt = r.get("target", "") or ""
            if len(tgt) > TARGET_MAX:
                r["target"] = tgt[:TARGET_MAX] + "..."
        for a in t["agents"]:
            a.pop("ts_utc_last", None)
            desc = a.get("description", "") or ""
            if len(desc) > DESC_MAX:
                a["description"] = desc[:DESC_MAX] + "..."

    # 공동출현 (cross-turn)
    cooc = {}
    for t in turns_list:
        nodes = []
        for r in t["reads"]:
            nodes.append(("md", r["file"]))
        for r in t["tools"]:
            target = r.get("target", "")
            label = f'{r["tool"]}:{target[:30]}'
            nodes.append(("tool", label))
        # 모든 쌍에 대해 공동출현 카운트
        for i in range(len(nodes)):
            for j in range(i + 1, len(nodes)):
                a_kind, a = nodes[i]
                b_kind, b = nodes[j]
                if a > b:
                    a, b, a_kind, b_kind = b, a, b_kind, a_kind
                key = (a_kind, a, b_kind, b)
                cooc[key] = cooc.get(key, 0) + 1

    co_list = [
        {"a_kind": k[0], "a": k[1], "b_kind": k[2], "b": k[3], "count": v}
        for k, v in cooc.items() if v >= 1
    ]
    co_list.sort(key=lambda x: -x["count"])

    # Sankey: prompt(workflow keyword) -> md category -> tool
    def prompt_to_kw(p):
        p = (p or "").lower()
        kws = []
        for kw in ["sso", "기능", "버그", "리팩터", "ui", "쿼리", "배포", "문서", "ultrathink"]:
            if kw in p:
                kws.append(kw)
        return kws[0] if kws else "general"

    sankey_links = {}  # (src, tgt) -> count
    for t in turns_list:
        kw = prompt_to_kw(t.get("prompt_preview", ""))
        for r in t["reads"]:
            cat = r.get("category", "other")
            sankey_links[("kw:" + kw, "cat:" + cat)] = sankey_links.get(("kw:" + kw, "cat:" + cat), 0) + 1
        # md->tool: 마지막 read 이후의 tool 만 그림
        if t["reads"] and t["tools"]:
            last_cat = t["reads"][-1]["category"]
            for r in t["tools"]:
                tool = r.get("tool", "")
                sankey_links[("cat:" + last_cat, "tool:" + tool)] = sankey_links.get(("cat:" + last_cat, "tool:" + tool), 0) + 1

    # 노드 ID 빌드
    sankey_node_set = set()
    for (s, tg) in sankey_links.keys():
        sankey_node_set.add(s)
        sankey_node_set.add(tg)
    sankey_nodes = sorted(sankey_node_set)
    node_idx = {n: i for i, n in enumerate(sankey_nodes)}
    sankey_link_arr = [
        {"source": node_idx[s], "target": node_idx[tg], "value": v}
        for (s, tg), v in sankey_links.items()
    ]

    return {
        "turns": turns_list,
        "co_occurrence": co_list[:200],  # cap
        "sankey": {
            "nodes": [{"id": i, "name": n} for n, i in node_idx.items()],
            "links": sankey_link_arr,
        },
    }

