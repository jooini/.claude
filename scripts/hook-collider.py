#!/usr/bin/env python3
"""
Hook Collider — 79개 훅의 의미론적 충돌/중복 감지.

분석 차원:
1. settings.json 중복 등록 (같은 훅이 같은 이벤트에 2번+)
2. 같은 이벤트의 동일 트리거 키워드 (예: commit-* 4개가 모두 git commit에 반응)
3. 외부 호출 충돌 (gemma/gemini/codex CLI를 같은 이벤트에서 동시 호출)
4. 출력 채널 경쟁 (stderr/stdout에 동시 출력하는 훅들)
5. 같은 파일 read/write 경쟁
6. 실행 시간이 긴 훅 (latency 측정)

출력:
- ~/.claude/cache/hook-audit.md (마크다운 리포트)
- ~/.claude/cache/hook-audit.json (구조화 데이터)
"""

import json
import re
import sys
import argparse
import subprocess
from pathlib import Path
from collections import defaultdict, Counter

HOOKS_DIR = Path.home() / ".claude/hooks"
SETTINGS = Path.home() / ".claude/settings.json"
OUT_MD = Path.home() / ".claude/cache/hook-audit.md"
OUT_JSON = Path.home() / ".claude/cache/hook-audit.json"

# 외부 CLI 패턴
CLI_PATTERNS = {
    "gemma": re.compile(r"\b(ini|qwen-cli|qwen3\.5|qwen2\.5-coder|gemma4|ollama)\b"),
    "gemini": re.compile(r"\bgemini\s+(-p|--prompt|generate)\b"),
    "codex": re.compile(r"\bcodex\s+(exec|--skip-git-repo-check|exec --)"),
    "git": re.compile(r"\bgit\s+(diff|log|status|show|blame)\b"),
    "obsidian_write": re.compile(r"weaversbrain.*\.md|>>\s*.*weaversbrain"),
    "rag_write": re.compile(r"local-rag|rag-index|ingest_file"),
    "decision_capture": re.compile(r"decision[-_]capture|decision\.md"),
}

OUTPUT_CHANNELS = {
    "stderr": re.compile(r">&\s*2|>&2|stderr"),
    "stdout": re.compile(r"echo\s+(?!.*>&2)|printf\s+(?!.*>&2)"),
    "exit_block": re.compile(r"exit\s+1|exit\s+2|return\s+1"),
}


def load_settings():
    if not SETTINGS.exists():
        return {}
    try:
        return json.loads(SETTINGS.read_text())
    except Exception:
        return {}


def get_event_registrations(settings):
    """returns {event: [(hook_basename, matcher), ...]}"""
    out = defaultdict(list)
    for event, configs in settings.get("hooks", {}).items():
        if not isinstance(configs, list):
            continue
        for cfg in configs:
            matcher = cfg.get("matcher", "")
            for h in cfg.get("hooks", []):
                cmd = h.get("command", "")
                if "/hooks/" in cmd:
                    base = cmd.split("/")[-1].split()[0]
                    out[event].append((base, matcher))
                elif cmd.endswith(".sh") or "claude" in cmd:
                    base = cmd.split("/")[-1].split()[0]
                    out[event].append((base, matcher))
    return dict(out)


def analyze_hook_content(hook_path):
    """Returns dict of features for one hook script."""
    try:
        text = hook_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return {}

    features = {
        "size_bytes": len(text.encode("utf-8")),
        "lines": text.count("\n"),
        "calls": [],
        "reads": [],
        "writes": [],
        "channels": [],
        "trigger_keywords": [],
    }

    for cli, pat in CLI_PATTERNS.items():
        if pat.search(text):
            features["calls"].append(cli)

    for ch, pat in OUTPUT_CHANNELS.items():
        if pat.search(text):
            features["channels"].append(ch)

    write_targets = re.findall(r">{1,2}\s*([^\s|;&]+\.(?:md|json|jsonl|tsv|log|txt))", text)
    features["writes"] = list(set(write_targets[:10]))

    trigger_patterns = {
        "commit": r"\bcommit\b",
        "diff": r"\bgit diff\b",
        "test_failure": r"\b(test.*fail|pytest|jest|FAIL)\b",
        "edit_tool": r"\b(Edit|Write|MultiEdit)\b",
        "bash_tool": r'"Bash"|tool_name.*Bash',
        "agent_event": r"agent_(start|end|complete)|SubagentStop",
        "session_event": r"SessionStart|SessionEnd|Stop\b",
        "korean_text": r"한국|한글|korean",
        "error_keyword": r"error|에러|오류|실패",
        "cwd_change": r"CwdChanged|cwd.*change",
    }
    for kw, pat in trigger_patterns.items():
        if re.search(pat, text, re.IGNORECASE):
            features["trigger_keywords"].append(kw)

    return features


def detect_collisions(event_regs, hook_features):
    findings = {
        "duplicate_registrations": [],
        "trigger_keyword_clusters": [],
        "cli_call_clusters": [],
        "write_target_conflicts": [],
        "size_outliers": [],
    }

    # 진짜 중복: 같은 (event, hook, matcher) 가 2번 이상이면 중복
    # 다른 matcher로 같은 hook이 있는 건 의도된 분기
    for event, entries in event_regs.items():
        cnt = Counter(entries)
        for (hook, matcher), n in cnt.items():
            if n > 1:
                findings["duplicate_registrations"].append({
                    "event": event,
                    "hook": hook,
                    "matcher": matcher or "(none)",
                    "count": n,
                })

    for event, entries in event_regs.items():
        hooks = [h for h, _ in entries]
        kw_to_hooks = defaultdict(list)
        for h in set(hooks):
            kws = hook_features.get(h, {}).get("trigger_keywords", [])
            for kw in kws:
                kw_to_hooks[kw].append(h)
        for kw, hs in kw_to_hooks.items():
            if len(hs) >= 3:
                findings["trigger_keyword_clusters"].append({
                    "event": event,
                    "trigger": kw,
                    "hooks": sorted(set(hs)),
                    "count": len(set(hs)),
                })

    for event, entries in event_regs.items():
        hooks = [h for h, _ in entries]
        cli_to_hooks = defaultdict(list)
        for h in set(hooks):
            for cli in hook_features.get(h, {}).get("calls", []):
                cli_to_hooks[cli].append(h)
        for cli, hs in cli_to_hooks.items():
            if len(set(hs)) >= 2:
                findings["cli_call_clusters"].append({
                    "event": event,
                    "cli": cli,
                    "hooks": sorted(set(hs)),
                    "count": len(set(hs)),
                })

    write_to_hooks = defaultdict(list)
    for h, f in hook_features.items():
        for w in f.get("writes", []):
            write_to_hooks[w].append(h)
    for target, hs in write_to_hooks.items():
        if len(hs) >= 2:
            findings["write_target_conflicts"].append({
                "target": target,
                "hooks": sorted(set(hs)),
            })

    sizes = [(h, f.get("size_bytes", 0)) for h, f in hook_features.items()]
    sizes.sort(key=lambda x: -x[1])
    findings["size_outliers"] = [{"hook": h, "bytes": b} for h, b in sizes[:5]]

    return findings


def write_report(event_regs, hook_features, findings):
    OUT_MD.parent.mkdir(parents=True, exist_ok=True)

    total_hooks = len(hook_features)
    total_registrations = sum(len(v) for v in event_regs.values())

    lines = []
    lines.append("# Hook Collider Audit Report")
    lines.append("")
    lines.append(f"- 훅 파일: {total_hooks}개")
    lines.append(f"- 활성 등록: {total_registrations}개")
    lines.append(f"- 이벤트 종류: {len(event_regs)}개")
    lines.append("")

    lines.append("## 1. 진짜 중복 등록 (같은 이벤트+같은 matcher 에 같은 훅 2번+)")
    lines.append("")
    if findings["duplicate_registrations"]:
        lines.append("| 이벤트 | 훅 | matcher | 횟수 |")
        lines.append("|---|---|---|---|")
        for d in findings["duplicate_registrations"]:
            lines.append(f"| {d['event']} | `{d['hook']}` | `{d['matcher']}` | **{d['count']}** |")
    else:
        lines.append("(없음)")
    lines.append("")

    lines.append("## 2. 트리거 키워드 클러스터 (같은 이벤트에서 같은 트리거에 반응하는 훅 3+개)")
    lines.append("")
    if findings["trigger_keyword_clusters"]:
        for c in findings["trigger_keyword_clusters"]:
            lines.append(f"### {c['event']} / `{c['trigger']}` — {c['count']}개 훅")
            for h in c["hooks"]:
                lines.append(f"- `{h}`")
            lines.append("")
    else:
        lines.append("(없음)")
    lines.append("")

    lines.append("## 3. 외부 CLI 호출 클러스터 (같은 이벤트에서 같은 CLI를 여러 훅이 동시 호출)")
    lines.append("")
    if findings["cli_call_clusters"]:
        for c in findings["cli_call_clusters"]:
            lines.append(f"### {c['event']} / `{c['cli']}` — {c['count']}개 훅")
            for h in c["hooks"]:
                lines.append(f"- `{h}`")
            lines.append("")
    else:
        lines.append("(없음)")
    lines.append("")

    lines.append("## 4. 쓰기 경쟁 (같은 파일에 여러 훅이 append/write)")
    lines.append("")
    if findings["write_target_conflicts"]:
        for c in findings["write_target_conflicts"]:
            lines.append(f"### `{c['target']}`")
            for h in c["hooks"]:
                lines.append(f"- `{h}`")
            lines.append("")
    else:
        lines.append("(없음)")
    lines.append("")

    lines.append("## 5. 크기 이상치 (가장 큰 훅 5개 — 정리 후보)")
    lines.append("")
    lines.append("| 훅 | 크기 |")
    lines.append("|---|---|")
    for o in findings["size_outliers"]:
        lines.append(f"| `{o['hook']}` | {o['bytes']:,} bytes |")
    lines.append("")

    lines.append("## 권장 조치")
    lines.append("")
    if findings["duplicate_registrations"]:
        lines.append("- 🔴 **중복 등록 즉시 제거** (settings.json 정리)")
    if findings["trigger_keyword_clusters"]:
        cnts = [c['count'] for c in findings["trigger_keyword_clusters"]]
        if cnts and max(cnts) >= 4:
            lines.append("- 🟠 **클러스터링된 훅 통합 검토** (commit/error 류 4+개 동시 발동)")
    if findings["cli_call_clusters"]:
        lines.append("- 🟡 **외부 CLI 캐싱** (같은 CLI를 여러 훅이 호출 시 결과 공유)")
    if findings["write_target_conflicts"]:
        lines.append("- 🟡 **쓰기 경쟁 파일은 락/큐 도입** 또는 단일 훅으로 합치기")

    OUT_MD.write_text("\n".join(lines), encoding="utf-8")

    OUT_JSON.write_text(json.dumps({
        "total_hooks": total_hooks,
        "total_registrations": total_registrations,
        "events": event_regs,
        "findings": findings,
    }, indent=2, ensure_ascii=False), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--show", action="store_true", help="리포트 stdout 출력")
    args = ap.parse_args()

    settings = load_settings()
    event_regs = get_event_registrations(settings)

    hook_features = {}
    for hook_path in HOOKS_DIR.glob("*.sh"):
        hook_features[hook_path.name] = analyze_hook_content(hook_path)

    findings = detect_collisions(event_regs, hook_features)

    write_report(event_regs, hook_features, findings)

    print(f"리포트: {OUT_MD}", file=sys.stderr)
    print(f"  훅 파일: {len(hook_features)}, 등록: {sum(len(v) for v in event_regs.values())}", file=sys.stderr)
    print(f"  중복 등록: {len(findings['duplicate_registrations'])}", file=sys.stderr)
    print(f"  트리거 클러스터: {len(findings['trigger_keyword_clusters'])}", file=sys.stderr)
    print(f"  CLI 클러스터: {len(findings['cli_call_clusters'])}", file=sys.stderr)
    print(f"  쓰기 충돌: {len(findings['write_target_conflicts'])}", file=sys.stderr)

    if args.show:
        print(OUT_MD.read_text())


if __name__ == "__main__":
    main()
