#!/usr/bin/env python3
"""
과거 transcript JSONL 들에서 .md Read / Bash·Edit·Write 추출 →
md-live JSONL (turn_id 포함) 로 백필.

기본: 최근 7일치, --days N 으로 변경 가능.
중복 방지: 기존 (turn_id, ts_utc, file/target) 같은 줄이 있으면 스킵.
"""
import json
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime, timedelta, timezone

PROJECTS_DIR = Path.home() / ".claude" / "projects" / "-Users-leonard"
LIVE_DIR = Path.home() / ".claude" / "cache" / "md-live"
LIVE_DIR.mkdir(parents=True, exist_ok=True)


MD_CATEGORIES = [
    ("claude_md", lambda p: p.endswith("/CLAUDE.md")),
    ("memory", lambda p: p.endswith("/MEMORY.md") or "/memory/" in p),
    ("workflow", lambda p: "/workflows/" in p),
    ("skill", lambda p: "/skills/" in p and (p.endswith("/skill.md") or p.endswith("/SKILL.md"))),
    ("agent", lambda p: "/agents-src/" in p or "/agents/builds/" in p or "/agents/" in p),
    ("knowledge", lambda p: "/knowledge/" in p),
]


def categorize(path):
    for cat, pred in MD_CATEGORIES:
        if pred(path):
            return cat
    return "other"


def is_md(path):
    return path.endswith(".md") or path.endswith("/CLAUDE.md") or path.endswith("/MEMORY.md") \
        or path.endswith("/skill.md") or path.endswith("/SKILL.md")


def parse_subagent(path, agent_type=None):
    """
    subagent jsonl 파싱 — 그 안에서 읽은 .md 파일들 추출.
    Returns:
      {
        'agent_id': str,
        'agent_type': str,
        'first_ts_utc': str,        # 첫 이벤트 시각 (메인 turn 매칭용)
        'parent_tool_use_id': str,  # 매칭 키
        'reads': [{ts_utc, file, category}],  # 그 agent 가 읽은 .md
      }
    """
    info = {
        'agent_id': '',
        'agent_type': agent_type or 'general-purpose',
        'first_ts_utc': '',
        'parent_tool_use_id': '',
        'reads': [],
    }
    try:
        with path.open() as f:
            for ln in f:
                try: d = json.loads(ln)
                except: continue
                if not info['agent_id']:
                    info['agent_id'] = d.get('agentId', '')
                if not info['parent_tool_use_id']:
                    info['parent_tool_use_id'] = d.get('parentToolUseID', '')
                ts_str = d.get('timestamp', '')
                if ts_str and not info['first_ts_utc']:
                    try:
                        ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                        info['first_ts_utc'] = ts.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                    except: pass
                if d.get('type') == 'assistant':
                    msg = d.get('message', {})
                    contents = msg.get('content', [])
                    if not isinstance(contents, list): continue
                    for c in contents:
                        if not isinstance(c, dict) or c.get('type') != 'tool_use': continue
                        if c.get('name') != 'Read': continue
                        fp = (c.get('input', {}) or {}).get('file_path', '')
                        if not is_md(fp): continue
                        try:
                            r_ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                            r_ts_utc = r_ts.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
                        except:
                            r_ts_utc = info['first_ts_utc']
                        info['reads'].append({
                            'ts_utc': r_ts_utc,
                            'file': fp,
                            'category': categorize(fp),
                        })
    except Exception as e:
        print(f"  ! subagent parse error {path.name}: {e}", file=sys.stderr)
    return info


def parse_transcript(path, since_utc):
    """
    Return:
      turns: list of {turn_id, session, ts_utc, prompt_preview}
      reads: list of {turn_id, session, ts_utc, ts, category, file}
      tools: list of {turn_id, session, ts_utc, ts, tool, target}
    """
    turns_seen = {}
    reads = []
    tools = []
    agents = []
    session = path.stem[:8]
    current_turn_id = None

    try:
        with path.open() as f:
            for ln in f:
                try:
                    d = json.loads(ln)
                except Exception:
                    continue
                ts_str = d.get("timestamp", "")
                if not ts_str:
                    continue
                try:
                    ts = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                except Exception:
                    continue
                if ts < since_utc:
                    continue

                ts_utc = ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                ts_local = ts.astimezone().strftime("%Y-%m-%dT%H:%M:%S")
                pid = d.get("promptId")

                # turn 시작 (real user prompt)
                if d.get("type") == "user" and "toolUseResult" not in d and pid:
                    msg = d.get("message", {})
                    content = msg.get("content", "") if isinstance(msg, dict) else ""
                    if isinstance(content, str) and content.strip():
                        current_turn_id = pid
                        if pid not in turns_seen:
                            turns_seen[pid] = {
                                "turn_id": pid,
                                "session": session,
                                "ts_utc": ts_utc,
                                "prompt_preview": content.replace("\n", " ").replace("\r", " "),
                            }

                # assistant 의 tool_use
                if d.get("type") == "assistant":
                    msg = d.get("message", {})
                    contents = msg.get("content", []) if isinstance(msg, dict) else []
                    if not isinstance(contents, list):
                        continue
                    turn_id = pid or current_turn_id or ""
                    if not turn_id:
                        continue
                    for c in contents:
                        if not isinstance(c, dict) or c.get("type") != "tool_use":
                            continue
                        name = c.get("name", "")
                        inp = c.get("input", {}) or {}
                        if name == "Read":
                            fp = inp.get("file_path", "")
                            if is_md(fp):
                                reads.append({
                                    "ts_utc": ts_utc,
                                    "ts": ts_local,
                                    "session": session,
                                    "turn_id": turn_id,
                                    "category": categorize(fp),
                                    "file": fp,
                                })
                        elif name == "Agent" or name == "Task":
                            agent = inp.get("subagent_type", "general-purpose") or "general-purpose"
                            desc = (inp.get("description", "") or "").replace("\n", " ")
                            agents.append({
                                "ts_utc": ts_utc,
                                "ts": ts_local,
                                "session": session,
                                "turn_id": turn_id,
                                "agent": agent,
                                "description": desc,
                            })
                        elif name in ("Bash", "Edit", "Write", "MultiEdit"):
                            if name == "Bash":
                                target = (inp.get("command", "") or "").replace("\n", " ")
                            else:
                                target = inp.get("file_path", "") or ""
                            tools.append({
                                "ts_utc": ts_utc,
                                "ts": ts_local,
                                "session": session,
                                "turn_id": turn_id,
                                "tool": name,
                                "target": target,
                            })
    except Exception as e:
        print(f"  ! parse error {path.name}: {e}", file=sys.stderr)

    return list(turns_seen.values()), reads, tools, agents


def load_existing_keys():
    """이미 기록된 (turn_id, ts_utc, file/target) 키 셋 — 중복 방지."""
    turns_set = set()
    reads_set = set()
    tools_set = set()

    turns_path = LIVE_DIR / "turns.jsonl"
    if turns_path.exists():
        for ln in turns_path.read_text().splitlines():
            try:
                d = json.loads(ln)
                turns_set.add(d.get("turn_id", ""))
            except Exception:
                pass

    agents_set = set()
    # reads / tools / agents 는 일별 파일이 있을 수 있어 모두 스캔
    for f in LIVE_DIR.glob("*.jsonl"):
        if f.name == "turns.jsonl":
            continue
        for ln in f.read_text().splitlines():
            try:
                d = json.loads(ln)
            except Exception:
                continue
            tid = d.get("turn_id", "")
            ts = d.get("ts_utc", "")
            if "agent" in d:
                agents_set.add((tid, ts, d.get("agent", ""), d.get("description", "")))
            elif "tool" in d:
                tools_set.add((tid, ts, d.get("tool", ""), d.get("target", "")))
            elif "file" in d:
                reads_set.add((tid, ts, d.get("file", "")))

    return turns_set, reads_set, tools_set, agents_set


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=7, help="최근 N 일 (default 7)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    since_utc = datetime.now(timezone.utc) - timedelta(days=args.days)
    print(f"📅 since: {since_utc.isoformat()}")

    transcripts = sorted(PROJECTS_DIR.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    # mtime 이 since 보다 이전인 파일은 스킵
    transcripts = [p for p in transcripts if datetime.fromtimestamp(p.stat().st_mtime, tz=timezone.utc) >= since_utc]
    print(f"📄 candidate transcripts: {len(transcripts)}")

    all_turns, all_reads, all_tools, all_agents = [], [], [], []
    all_agent_reads = []  # subagent 들이 spawn 시 읽은 .md
    for p in transcripts:
        turns, reads, tools, agents = parse_transcript(p, since_utc)
        all_turns.extend(turns)
        all_reads.extend(reads)
        all_tools.extend(tools)
        all_agents.extend(agents)

        # 같은 메인 session 의 subagents 디렉토리 스캔
        # transcript 경로: .../{proj}/{session_uuid}.jsonl
        # subagents:        .../{proj}/{session_uuid}/subagents/agent-*.jsonl
        sub_dir = p.parent / p.stem / 'subagents'
        sub_count = 0
        if sub_dir.exists():
            session = p.stem[:8]
            for sub_jsonl in sub_dir.glob('agent-*.jsonl'):
                # meta.json 으로 agent type 확인
                meta_file = sub_dir / f"{sub_jsonl.stem}.meta.json"
                agent_type = None
                if meta_file.exists():
                    try:
                        agent_type = json.loads(meta_file.read_text()).get('agentType')
                    except: pass
                info = parse_subagent(sub_jsonl, agent_type)
                if info['first_ts_utc'] < since_utc.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'):
                    continue
                # 각 read 를 (agent_id 와 함께) 별도 row 로
                # match_confidence: parent_tool_use_id 있으면 high, agent_id+ts만 있으면 medium, 둘 다 없으면 low
                if info['parent_tool_use_id']:
                    confidence = 'high'
                elif info['agent_id'] and info['first_ts_utc']:
                    confidence = 'medium'
                else:
                    confidence = 'low'
                for r in info['reads']:
                    all_agent_reads.append({
                        'ts_utc': r['ts_utc'],
                        'session': session,
                        'parent_tool_use_id': info['parent_tool_use_id'],
                        'agent_id': info['agent_id'],
                        'agent_type': info['agent_type'],
                        'agent_first_ts_utc': info['first_ts_utc'],
                        'match_confidence': confidence,
                        'category': r['category'],
                        'file': r['file'],
                    })
                sub_count += 1
        if turns or reads or tools or agents or sub_count:
            print(f"  ✓ {p.name[:8]}: turns={len(turns)}, reads={len(reads)}, tools={len(tools)}, agents={len(agents)}, subs={sub_count}")

    print(f"\n🔢 parsed total: {len(all_turns)} turns, {len(all_reads)} reads, {len(all_tools)} tools, {len(all_agents)} agents, {len(all_agent_reads)} agent_reads")

    # 중복 제거
    turns_set, reads_set, tools_set, agents_set = load_existing_keys()
    new_turns = [t for t in all_turns if t["turn_id"] not in turns_set]
    new_reads = [r for r in all_reads if (r["turn_id"], r["ts_utc"], r["file"]) not in reads_set]
    new_tools = [r for r in all_tools if (r["turn_id"], r["ts_utc"], r["tool"], r["target"]) not in tools_set]
    new_agents = [r for r in all_agents if (r["turn_id"], r["ts_utc"], r["agent"], r["description"]) not in agents_set]

    print(f"➕ new (after dedup): {len(new_turns)} turns, {len(new_reads)} reads, {len(new_tools)} tools, {len(new_agents)} agents")

    if args.dry_run:
        print("(dry-run — 쓰기 안 함)")
        return

    # turns.jsonl 에 append (시간순 정렬)
    new_turns.sort(key=lambda x: x["ts_utc"])
    with (LIVE_DIR / "turns.jsonl").open("a") as f:
        for t in new_turns:
            f.write(json.dumps(t, ensure_ascii=False) + "\n")

    # reads → 일별 파일에 분배
    by_day_reads = {}
    for r in new_reads:
        # ts 의 날짜 (KST 기준) 사용 — 기존 파일명 컨벤션 유지
        day = r["ts"][:10]
        by_day_reads.setdefault(day, []).append(r)
    for day, rows in by_day_reads.items():
        rows.sort(key=lambda x: x["ts_utc"])
        with (LIVE_DIR / f"{day}.jsonl").open("a") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # tools → tool-trace-{day}.jsonl
    by_day_tools = {}
    for r in new_tools:
        day = r["ts"][:10]
        by_day_tools.setdefault(day, []).append(r)
    for day, rows in by_day_tools.items():
        rows.sort(key=lambda x: x["ts_utc"])
        with (LIVE_DIR / f"tool-trace-{day}.jsonl").open("a") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # agents → agent-trace-{day}.jsonl
    by_day_agents = {}
    for r in new_agents:
        day = r["ts"][:10]
        by_day_agents.setdefault(day, []).append(r)
    for day, rows in by_day_agents.items():
        rows.sort(key=lambda x: x["ts_utc"])
        with (LIVE_DIR / f"agent-trace-{day}.jsonl").open("a") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # agent_reads → agent-reads.jsonl (단일 파일, 매칭은 ts/parent_tool_use_id 로)
    if all_agent_reads:
        # 기존 키 로딩 (중복 제거)
        existing_ar = set()
        ar_file = LIVE_DIR / 'agent-reads.jsonl'
        if ar_file.exists():
            for ln in ar_file.read_text().splitlines():
                try:
                    d = json.loads(ln)
                    existing_ar.add((d.get('agent_id',''), d.get('ts_utc',''), d.get('file','')))
                except: pass
        new_ar = [r for r in all_agent_reads
                  if (r['agent_id'], r['ts_utc'], r['file']) not in existing_ar]
        new_ar.sort(key=lambda x: x['ts_utc'])
        with ar_file.open('a') as f:
            for r in new_ar:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"  + agent_reads: {len(new_ar)} new (총 {len(all_agent_reads)} parsed)")

    print(f"✅ 백필 완료: {LIVE_DIR}")


if __name__ == "__main__":
    main()
