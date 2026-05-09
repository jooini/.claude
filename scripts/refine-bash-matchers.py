#!/usr/bin/env python3
"""
PreToolUse Bash 매처를 세분화하여 부하 감소.

전: matcher='Bash' 단일 그룹에 9개 훅
후:
  - matcher='Bash' (모든 Bash): bash-codegen-block, danger-keyword-detect
  - matcher='Bash(git commit*)': gemma-commit-draft, gemma-commit-convention,
                                  commit-korean-check, commit-no-coauthor,
                                  gemini-large-diff-prescan,
                                  gemma-korean-translate-gate
  - matcher='Bash(gh pr*)': pr-create-codex-remind,
                             gemma-korean-translate-gate (중복)
"""
import json
import re
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"

GROUPS = {
    "Bash": [
        "bash-codegen-block.sh",
        "danger-keyword-detect.sh",
    ],
    "Bash(git commit*)": [
        "gemma-commit-draft.sh",
        "gemma-commit-convention.sh",
        "commit-korean-check.sh",
        "commit-no-coauthor.sh",
        "gemini-large-diff-prescan.sh",
        "gemma-korean-translate-gate.sh",
    ],
    "Bash(gh pr*)": [
        "pr-create-codex-remind.sh",
        "gemma-korean-translate-gate.sh",
    ],
}

def find_hook_command(item, name):
    """기존 PreToolUse Bash 그룹에서 훅 이름으로 command 객체 찾아 반환"""
    for h in item.get("hooks", []):
        cmd = h.get("command", "")
        if f"/hooks/{name}" in cmd:
            return h
    return None

def main():
    data = json.loads(SETTINGS.read_text())
    pre = data["hooks"].get("PreToolUse", [])

    # 기존 matcher='Bash' 그룹 찾기
    bash_idx = None
    for i, item in enumerate(pre):
        if item.get("matcher") == "Bash":
            bash_idx = i
            break
    if bash_idx is None:
        print("ERROR: PreToolUse Bash group not found")
        return

    old_group = pre[bash_idx]
    print(f"Original group: {len(old_group['hooks'])} hooks under matcher='Bash'")

    # 새 그룹 빌드
    new_groups = []
    for matcher, names in GROUPS.items():
        hooks = []
        for name in names:
            h = find_hook_command(old_group, name)
            if h:
                hooks.append(dict(h))
            else:
                print(f"WARN: hook {name} not found in original group")
        new_groups.append({"matcher": matcher, "hooks": hooks})
        print(f"  matcher={matcher!r}: {len(hooks)} hooks")

    # 검증: 원본의 모든 훅이 새 그룹들에 (1번 이상) 옮겨졌는지
    original_names = set()
    for h in old_group["hooks"]:
        m = re.search(r"/hooks/([\w-]+\.sh)", h.get("command", ""))
        if m:
            original_names.add(m.group(1))
    moved_names = set()
    for g in new_groups:
        for h in g["hooks"]:
            m = re.search(r"/hooks/([\w-]+\.sh)", h.get("command", ""))
            if m:
                moved_names.add(m.group(1))
    missing = original_names - moved_names
    if missing:
        print(f"ERROR: hooks not moved to any new group: {missing}")
        return
    print(f"All {len(original_names)} original hooks are accounted for.")

    # 교체: 기존 Bash 그룹을 새 3개 그룹으로 대체
    pre[bash_idx:bash_idx + 1] = new_groups

    SETTINGS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"\nSaved: {SETTINGS}")

if __name__ == "__main__":
    main()
