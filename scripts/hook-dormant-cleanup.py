#!/usr/bin/env python3
"""
hook-dormant-cleanup.py

7일+ 동안 dormant 상태인 hook을 자동 식별하고 (옵션) 비활성화.

dormant 정의:
  - 최근 N일 호출 100회 이상
  - output(side==output) 0회
  - 화이트리스트(데이터수집/가드/시스템성) 제외

사용:
  python3 ~/.claude/scripts/hook-dormant-cleanup.py [days=7]            # 분석만
  python3 ~/.claude/scripts/hook-dormant-cleanup.py [days=7] --apply    # 비활성 적용
  python3 ~/.claude/scripts/hook-dormant-cleanup.py [days=7] --revert   # 롤백 (비활성 해제)

비활성 방법:
  ~/.claude/hooks/{hook}.sh → ~/.claude/hooks/_disabled/{hook}.sh.dormant-{date}
  + settings.json에서 해당 hook 등록 제거 (백업 후)

롤백:
  _disabled/ 에서 다시 hooks/로 mv
  settings.json 백업본으로 복구
"""
import json
import sys
import shutil
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict

HOME = Path.home()
HOOKS_DIR = HOME / ".claude" / "hooks"
DISABLED_DIR = HOOKS_DIR / "_disabled"
SETTINGS = HOME / ".claude" / "settings.json"
TRACE_DIR = HOME / ".claude" / "cache" / "hook-trace"

WHITELIST = {
    # 데이터 수집 (jsonl 기록만, output 없는 게 정상)
    "bash-postproc-async", "bash-postproc-sync",  # 2026-05-14 통합본
    "md-read-trace", "agent-trace", "agent-usage-log",
    "pipeline-metrics-log", "learning-note-auto-ingest", "decision-capture",
    "knowledge-change-rebuild", "rag-auto-index", "turn-marker",
    # 가드 (위험 패턴 검출 안 되면 noop이 정상)
    "bash-codegen-block", "danger-keyword-detect", "dangerous-command-detect",
    "closure-gate-stop", "closure-gate-session-start",
    # 시스템성
    "session-turn-counter", "self-reflection-inject", "qq-realtime-warning",
    "workflow-md-inject", "simple-query-ollama-route",
    # 카운터/추적 류
    "ultrathink-auto-trigger", "memory-search-suggest", "auto-scale-detect",
}


def analyze(days):
    cutoff = datetime.now() - timedelta(days=days)
    counts = defaultdict(lambda: {"total": 0, "output": 0})

    for f in TRACE_DIR.glob("*.jsonl"):
        try:
            d = datetime.strptime(f.stem, "%Y-%m-%d")
            if d < cutoff:
                continue
        except ValueError:
            continue
        try:
            for line in f.open():
                try:
                    r = json.loads(line)
                    h = r.get("hook", "")
                    if not h or h in WHITELIST:
                        continue
                    counts[h]["total"] += 1
                    if r.get("side") == "output":
                        counts[h]["output"] += 1
                except json.JSONDecodeError:
                    pass
        except OSError:
            pass

    dormant = sorted(
        [(h, c) for h, c in counts.items() if c["total"] >= 100 and c["output"] == 0],
        key=lambda x: -x[1]["total"],
    )
    return dormant


def apply_disable(dormant):
    """hook 파일을 _disabled/로 이동 + settings.json에서 등록 제거"""
    DISABLED_DIR.mkdir(exist_ok=True)
    today = datetime.now().strftime("%Y%m%d")

    # settings 백업
    backup = SETTINGS.with_suffix(f".json.bak-dormant-{today}")
    shutil.copy2(SETTINGS, backup)
    print(f"settings.json 백업: {backup}")

    with open(SETTINGS) as f:
        s = json.load(f)

    moved = []
    removed_from_settings = 0

    for hook_name, _ in dormant:
        src = HOOKS_DIR / f"{hook_name}.sh"
        if not src.exists():
            print(f"  ⚠️  {hook_name}.sh 파일 없음 — 스킵")
            continue
        dst = DISABLED_DIR / f"{hook_name}.sh.dormant-{today}"
        shutil.move(str(src), str(dst))
        moved.append((hook_name, dst))
        print(f"  ✅ 이동: {hook_name}.sh → _disabled/")

        # settings.json에서 등록 제거
        for ev_hooks in s.get("hooks", {}).values():
            for block in ev_hooks:
                hooks = block.get("hooks", [])
                block["hooks"] = [
                    h for h in hooks
                    if hook_name + ".sh" not in h.get("command", "")
                ]
                if len(block["hooks"]) != len(hooks):
                    removed_from_settings += len(hooks) - len(block["hooks"])

    with open(SETTINGS, "w") as f:
        json.dump(s, f, indent=2, ensure_ascii=False)

    print(f"\nsettings.json 등록 {removed_from_settings}건 제거")
    print(f"\n롤백 명령:")
    print(f"  python3 ~/.claude/scripts/hook-dormant-cleanup.py --revert {today}")
    return moved


def revert(date_tag):
    """_disabled/{name}.sh.dormant-{date} → hooks/{name}.sh 복원 + settings.json 롤백"""
    backup = SETTINGS.with_suffix(f".json.bak-dormant-{date_tag}")
    if not backup.exists():
        print(f"❌ settings 백업 없음: {backup}")
        return
    shutil.copy2(backup, SETTINGS)
    print(f"settings.json 복구: {backup} → {SETTINGS}")

    pattern = f".dormant-{date_tag}"
    restored = 0
    for f in DISABLED_DIR.glob(f"*{pattern}"):
        original_name = f.name.replace(pattern, "")
        target = HOOKS_DIR / original_name
        shutil.move(str(f), str(target))
        print(f"  ✅ 복원: {original_name}")
        restored += 1
    print(f"\n총 {restored}개 hook 복원")


def main():
    args = sys.argv[1:]
    apply_flag = "--apply" in args
    revert_flag = "--revert" in args
    args = [a for a in args if not a.startswith("--")]

    if revert_flag:
        if not args:
            print("Usage: --revert YYYYMMDD")
            return
        revert(args[0])
        return

    days = int(args[0]) if args else 7

    dormant = analyze(days)

    print(f"=== Dormant Hook Analysis (최근 {days}일) ===\n")
    if not dormant:
        print("✅ dormant hook 없음")
        return

    print(f"발견: {len(dormant)}개\n")
    for h, c in dormant:
        path = HOOKS_DIR / f"{h}.sh"
        exists = "✅" if path.exists() else "❌(파일없음)"
        print(f"  {exists} {h:40} 호출 {c['total']:>5}회 / output 0")

    if not apply_flag:
        print(f"\n--apply 없이 분석만 했습니다. 비활성화하려면:")
        print(f"  python3 ~/.claude/scripts/hook-dormant-cleanup.py {days} --apply")
        return

    print(f"\n--apply 실행 — 비활성화 진행:\n")
    moved = apply_disable(dormant)
    print(f"\n총 {len(moved)}개 hook 비활성화 완료")


if __name__ == "__main__":
    main()
