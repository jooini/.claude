#!/usr/bin/env python3
"""
Tool DNA — 82개 훅의 진화 트리 + deprecated 후보 자동 감지.

분석 차원:
1. **시간축**: mtime + 생성 추정 (가장 오래된 = ancestor 후보)
2. **코드 유사도**: shingled jaccard (3-gram 토큰) + 공통 헬퍼 호출 패턴
3. **명명 클러스터**: prefix (gemma- / gemini- / agent- / claude- / gemma- 등)
4. **이벤트 클러스터**: settings.json 내 어떤 이벤트에 등록됐나
5. **deprecated 신호**:
   - 90일+ 미수정 + settings.json 미등록
   - 같은 클러스터에 newer 변종 존재
   - .bak / .old / .orig 같은 형제 파일

출력:
- ~/.claude/cache/tool-dna.{md,json,dot}
- 가계도(dot/mermaid) + deprecated 후보 + 통합 제안
"""

import os
import re
import sys
import json
import argparse
import subprocess
from pathlib import Path
from collections import defaultdict, Counter
from datetime import datetime, timezone, timedelta

HOOKS_DIR = Path.home() / ".claude/hooks"
SETTINGS = Path.home() / ".claude/settings.json"
OUT_MD = Path.home() / ".claude/cache/tool-dna.md"
OUT_JSON = Path.home() / ".claude/cache/tool-dna.json"
OUT_DOT = Path.home() / ".claude/cache/tool-dna.dot"


def tokenize(text):
    # \w 는 re.UNICODE 기본 동작으로 한글/유니코드 식별자를 포함.
    # 숫자만으로 시작하는 토큰은 제외 (식별자 규칙 유지).
    return re.findall(r"[^\W\d][\w]*", text or "", flags=re.UNICODE)


# 유사도 비교에서 제외할 최소 토큰 수.
# 3줄짜리 stub 은 boilerplate 만 남아서 한글/문자열을 빼면 5~10 토큰이 전부 →
# 어떤 두 stub 도 jaccard 1.00 으로 잘못 매칭됨.
MIN_TOKENS_FOR_SIMILARITY = 20


def shingles(tokens, k=3):
    return set(tuple(tokens[i:i + k]) for i in range(len(tokens) - k + 1))


def jaccard(a, b):
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union if union else 0.0


def hook_prefix(name):
    base = name.replace(".sh", "")
    parts = base.split("-")
    if len(parts) <= 1:
        return base
    common_prefixes = {
        "gemma", "gemini", "agent", "claude", "claudemd", "commit", "session",
        "gemma", "qwen", "code", "decision", "delegation", "dependency",
        "error", "knowledge", "learning", "memory", "pipeline", "stop",
        "tool", "ultrathink", "workflow", "auto", "danger", "dangerous",
    }
    if parts[0].lower() in common_prefixes:
        return parts[0].lower()
    return parts[0].lower()


def load_hooks():
    hooks = {}
    for p in HOOKS_DIR.glob("*.sh"):
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            text = ""
        stat = p.stat()
        hooks[p.name] = {
            "name": p.name,
            "path": str(p),
            "size": stat.st_size,
            "mtime": stat.st_mtime,
            "mtime_iso": datetime.fromtimestamp(stat.st_mtime).isoformat()[:16],
            "lines": text.count("\n"),
            "tokens": tokenize(text),
            "text": text,
            "prefix": hook_prefix(p.name),
        }
    for h in hooks.values():
        h["shingles"] = shingles(h["tokens"], k=3)
    return hooks


def load_settings_registrations():
    """{hook_name: [(event, matcher), ...]}"""
    out = defaultdict(list)
    try:
        s = json.loads(SETTINGS.read_text())
    except Exception:
        return dict(out)
    for event, configs in s.get("hooks", {}).items():
        if not isinstance(configs, list):
            continue
        for cfg in configs:
            matcher = cfg.get("matcher", "")
            for h in cfg.get("hooks", []):
                cmd = h.get("command", "")
                if "/hooks/" in cmd:
                    base = cmd.split("/")[-1].split()[0]
                    out[base].append((event, matcher))
    return dict(out)


def load_router_calls():
    """
    동적 라우터(*-router.sh, turn-finalize.sh 등)가 호출하는 hook 이름 → [routers...].
    settings.json에 등록되지 않았어도 라우터가 호출하면 살아있는 hook.
    """
    called_by = defaultdict(list)
    hook_names = {p.name for p in HOOKS_DIR.glob("*.sh")}
    for p in HOOKS_DIR.glob("*.sh"):
        try:
            text = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for name in hook_names:
            if name == p.name:
                continue
            # 단순 부분문자열 매치 — router는 보통 "$HOOKS/foo.sh" 형태로 호출
            if name in text:
                called_by[name].append(p.name)
    return dict(called_by)


def find_siblings(hooks):
    """.bak / .old / .orig / 2 / new 같은 형제 파일 감지."""
    siblings = defaultdict(list)
    for name in hooks:
        stem = re.sub(r"(\.bak|\.old|\.orig|\.new|2|_v\d+|-old|-new)\.sh$", ".sh", name)
        if stem != name:
            siblings[stem].append(name)
    return dict(siblings)


def compute_pairs(hooks, threshold=0.3):
    """모든 쌍의 jaccard 유사도 계산. threshold 이상만 반환.

    너무 짧은 stub (MIN_TOKENS_FOR_SIMILARITY 미만)은 비교 제외 — 토큰이 부족하면
    boilerplate 만으로 jaccard 가 인위적으로 부풀려진다.
    """
    names = sorted(hooks.keys())
    pairs = []
    for i, a in enumerate(names):
        if len(hooks[a]["tokens"]) < MIN_TOKENS_FOR_SIMILARITY:
            continue
        for b in names[i + 1:]:
            if len(hooks[b]["tokens"]) < MIN_TOKENS_FOR_SIMILARITY:
                continue
            sim = jaccard(hooks[a]["shingles"], hooks[b]["shingles"])
            if sim >= threshold:
                pairs.append({
                    "a": a,
                    "b": b,
                    "similarity": round(sim, 3),
                    "size_diff": abs(hooks[a]["size"] - hooks[b]["size"]),
                    "mtime_a": hooks[a]["mtime_iso"],
                    "mtime_b": hooks[b]["mtime_iso"],
                })
    pairs.sort(key=lambda x: -x["similarity"])
    return pairs


def build_evolution_tree(hooks, pairs):
    """가계도 — 가장 오래된 노드를 ancestor로, 유사한 newer를 descendant로."""
    tree = defaultdict(list)
    visited = set()

    sorted_by_mtime = sorted(hooks.values(), key=lambda h: h["mtime"])
    pair_map = defaultdict(list)
    for p in pairs:
        pair_map[p["a"]].append(p)
        pair_map[p["b"]].append(p)

    # 각 hook에 대해 가장 유사한 older sibling을 parent로
    for h in sorted_by_mtime:
        my_pairs = pair_map.get(h["name"], [])
        best_parent = None
        best_sim = 0
        for p in my_pairs:
            other = p["b"] if p["a"] == h["name"] else p["a"]
            if hooks[other]["mtime"] < h["mtime"] and p["similarity"] > best_sim:
                best_sim = p["similarity"]
                best_parent = other
        if best_parent:
            tree[best_parent].append({
                "child": h["name"],
                "similarity": best_sim,
            })
    return dict(tree)


def detect_deprecated(hooks, registrations, siblings, pairs, router_calls, days=90):
    """deprecated 후보 감지. router_calls 가 호출하는 hook은 살아있는 것으로 간주."""
    candidates = []
    cutoff = datetime.now().timestamp() - days * 86400

    def is_alive(name):
        """settings.json 등록 OR 동적 라우터/다른 hook이 호출하면 살아있음."""
        return name in registrations or name in router_calls

    for name, h in hooks.items():
        reasons = []
        alive = is_alive(name)
        callers = router_calls.get(name, [])

        if h["mtime"] < cutoff and not alive:
            reasons.append(f"{days}일+ 미수정 + 어디서도 호출 안 됨")
        if not alive:
            reasons.append("settings.json 미등록 + 동적 호출 없음")
        if any(name in v for v in siblings.values()):
            reasons.append("형제 파일 (.bak/.old/번호 변종) 감지")

        same_prefix = [n for n, hh in hooks.items() if hh["prefix"] == h["prefix"] and n != name]
        if len(same_prefix) >= 3:
            newer_in_cluster = [n for n in same_prefix if hooks[n]["mtime"] > h["mtime"]]
            if len(newer_in_cluster) >= 2:
                high_sim_newer = [
                    p for p in pairs
                    if (p["a"] == name or p["b"] == name)
                    and p["similarity"] > 0.5
                ]
                if high_sim_newer:
                    reasons.append(f"{h['prefix']}- 클러스터에 newer 변종 {len(newer_in_cluster)}개 + 고유사도 짝")

        if h["lines"] < 10 and h["mtime"] < cutoff:
            reasons.append(f"매우 짧은 stub ({h['lines']}줄)")

        if reasons:
            candidates.append({
                "hook": name,
                "mtime": h["mtime_iso"],
                "size": h["size"],
                "lines": h["lines"],
                "reasons": reasons,
                "registered": name in registrations,
                "called_by": callers,
            })
    candidates.sort(key=lambda x: (-len(x["reasons"]), x["mtime"]))
    return candidates


def write_dot(hooks, tree, deprecated_names, out_path):
    lines = ["digraph ToolDNA {", '  rankdir="LR";', '  node [shape=box, fontname="Helvetica"];']
    color = {}
    for h in hooks.values():
        if h["name"] in deprecated_names:
            color[h["name"]] = "lightgray"
        else:
            color[h["name"]] = {
                "gemma": "lightgreen", "gemini": "lightblue", "qwen": "lightcyan",
                "agent": "lightyellow", "session": "wheat", "tool": "thistle",
                "decision": "pink", "delegation": "khaki", "commit": "lightcoral",
            }.get(h["prefix"], "white")

    for h in hooks.values():
        label = h["name"].replace(".sh", "")
        lines.append(f'  "{h["name"]}" [label="{label}\\n{h["mtime_iso"][:10]}", fillcolor="{color[h["name"]]}", style=filled];')

    for parent, children in tree.items():
        for c in children:
            lines.append(f'  "{parent}" -> "{c["child"]}" [label="{c["similarity"]:.2f}"];')

    lines.append("}")
    out_path.write_text("\n".join(lines), encoding="utf-8")


def write_md(hooks, tree, pairs, deprecated, registrations, siblings):
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    prefix_count = Counter(h["prefix"] for h in hooks.values())
    registered_count = sum(1 for n in hooks if n in registrations)

    lines = []
    lines.append("# Tool DNA — 훅 진화 트리")
    lines.append("")
    lines.append(f"- 훅 파일: {len(hooks)}")
    lines.append(f"- settings.json 등록: {registered_count}")
    lines.append(f"- 가계도 부모-자식 관계: {sum(len(v) for v in tree.values())}")
    lines.append(f"- 고유사도 쌍 (≥0.3): {len(pairs)}")
    lines.append(f"- deprecated 후보: {len(deprecated)}")
    lines.append("")

    lines.append("## 클러스터 분포")
    lines.append("")
    lines.append("| prefix | 개수 |")
    lines.append("|---|---|")
    for prefix, cnt in prefix_count.most_common(15):
        lines.append(f"| {prefix} | {cnt} |")
    lines.append("")

    lines.append("## 가계도 (parent → child, 유사도)")
    lines.append("")
    lines.append("```")
    for parent, children in sorted(tree.items()):
        for c in sorted(children, key=lambda x: -x["similarity"]):
            lines.append(f"  {parent} ──[{c['similarity']:.2f}]──> {c['child']}")
    lines.append("```")
    lines.append("")

    lines.append("## 고유사도 쌍 TOP 20 (통합 검토)")
    lines.append("")
    lines.append("| 유사도 | 훅 A (mtime) | 훅 B (mtime) |")
    lines.append("|---|---|---|")
    for p in pairs[:20]:
        lines.append(f"| {p['similarity']:.2f} | `{p['a']}` ({p['mtime_a'][:10]}) | `{p['b']}` ({p['mtime_b'][:10]}) |")
    lines.append("")

    lines.append("## Deprecated 후보 (정리/제거 검토)")
    lines.append("")
    if deprecated:
        for d in deprecated[:30]:
            status_bits = []
            if d['registered']:
                status_bits.append("등록됨")
            elif d.get('called_by'):
                status_bits.append(f"동적 호출됨 ({', '.join(d['called_by'])})")
            else:
                status_bits.append("미등록")
            lines.append(f"### `{d['hook']}` ({d['mtime'][:10]}, {d['lines']}줄, {', '.join(status_bits)})")
            for r in d["reasons"]:
                lines.append(f"- ⚠️ {r}")
            lines.append("")
        if len(deprecated) > 30:
            lines.append(f"... 외 {len(deprecated) - 30}건")
            lines.append("")
    else:
        lines.append("(없음)")
        lines.append("")

    if siblings:
        lines.append("## 형제 파일 (.bak / .old / 번호 변종)")
        lines.append("")
        for stem, sibs in siblings.items():
            lines.append(f"- `{stem}` → {', '.join(f'`{s}`' for s in sibs)}")
        lines.append("")

    lines.append("## 가시화")
    lines.append("")
    lines.append(f"DOT 그래프: `{OUT_DOT}`")
    lines.append("")
    lines.append("```bash")
    lines.append(f"dot -Tsvg {OUT_DOT} -o ~/.claude/cache/tool-dna.svg")
    lines.append("# 또는")
    lines.append(f"dot -Tpng {OUT_DOT} -o ~/.claude/cache/tool-dna.png")
    lines.append("```")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--threshold", type=float, default=0.3)
    ap.add_argument("--days", type=int, default=90, help="deprecated 후보 미수정 기준일")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    print(f"훅 분석 시작 — {HOOKS_DIR}", file=sys.stderr)
    hooks = load_hooks()
    print(f"  {len(hooks)}개 훅 로드", file=sys.stderr)

    registrations = load_settings_registrations()
    print(f"  {len(registrations)}개 등록 hook", file=sys.stderr)

    router_calls = load_router_calls()
    print(f"  {len(router_calls)}개 동적 호출 hook (router/다른 hook이 호출)", file=sys.stderr)

    siblings = find_siblings(hooks)
    print(f"  {len(siblings)}개 형제 그룹", file=sys.stderr)

    pairs = compute_pairs(hooks, threshold=args.threshold)
    print(f"  {len(pairs)}개 고유사도 쌍 (≥{args.threshold})", file=sys.stderr)

    tree = build_evolution_tree(hooks, pairs)
    print(f"  가계도 부모: {len(tree)}", file=sys.stderr)

    deprecated = detect_deprecated(hooks, registrations, siblings, pairs, router_calls, args.days)
    print(f"  deprecated 후보: {len(deprecated)}", file=sys.stderr)

    write_md(hooks, tree, pairs, deprecated, registrations, siblings)
    write_dot(hooks, tree, set(d["hook"] for d in deprecated), OUT_DOT)

    OUT_JSON.write_text(json.dumps({
        "total_hooks": len(hooks),
        "registered": len(registrations),
        "pairs_count": len(pairs),
        "deprecated_count": len(deprecated),
        "tree": tree,
        "pairs_top": pairs[:50],
        "deprecated": deprecated,
        "siblings": siblings,
    }, indent=2, ensure_ascii=False, default=str), encoding="utf-8")

    print(f"\n리포트:\n  {OUT_MD}\n  {OUT_DOT}\n  {OUT_JSON}", file=sys.stderr)

    if args.show:
        print(OUT_MD.read_text())


if __name__ == "__main__":
    main()
