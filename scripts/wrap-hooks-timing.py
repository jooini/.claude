#!/usr/bin/env python3
"""
settings.json의 hook command를 hook-timing wrapper로 감싸기.

사용:
    python3 wrap-hooks-timing.py [--dry-run] [--events EVENT,EVENT,...] [--unwrap]

대상 이벤트는 기본적으로 PostToolUse, PreToolUse, UserPromptSubmit (가장 자주 발동).
--unwrap 으로 wrapper 제거 가능.
"""
import json
import re
import sys
from pathlib import Path

SETTINGS = Path.home() / ".claude" / "settings.json"
WRAPPER = str(Path.home() / ".claude" / "hooks" / "_lib" / "hook-timing.sh")
HOOK_DIR = str(Path.home() / ".claude" / "hooks")

DEFAULT_EVENTS = ["PostToolUse", "PreToolUse", "UserPromptSubmit"]

def main():
    dry_run = "--dry-run" in sys.argv
    unwrap = "--unwrap" in sys.argv
    events = DEFAULT_EVENTS
    if "--events" in sys.argv:
        idx = sys.argv.index("--events")
        events = sys.argv[idx + 1].split(",")

    data = json.loads(SETTINGS.read_text())
    hooks = data.get("hooks", {})

    changed = 0
    for event_name in events:
        items = hooks.get(event_name, [])
        for item in items:
            for h in item.get("hooks", []):
                cmd = h.get("command", "")
                if unwrap:
                    m = re.match(r"^/bin/zsh\s+" + re.escape(WRAPPER) + r"\s+(.+)$", cmd)
                    if m:
                        new_cmd = m.group(1)
                        if new_cmd != cmd:
                            print(f"[{event_name}] UNWRAP: {cmd[:60]}... -> {new_cmd[:60]}...")
                            h["command"] = new_cmd
                            changed += 1
                else:
                    if WRAPPER in cmd:
                        continue
                    if HOOK_DIR not in cmd:
                        continue
                    if not cmd.endswith(".sh"):
                        continue
                    new_cmd = f"/bin/zsh {WRAPPER} {cmd.strip()}"
                    print(f"[{event_name}] WRAP: {cmd[:60]}... -> wrapped")
                    h["command"] = new_cmd
                    changed += 1

    print(f"\nTotal changed: {changed}")
    if dry_run:
        print("(dry-run, no write)")
        return
    if changed == 0:
        print("(nothing to do)")
        return

    SETTINGS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"Saved: {SETTINGS}")

if __name__ == "__main__":
    main()
