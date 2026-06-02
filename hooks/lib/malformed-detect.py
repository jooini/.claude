#!/usr/bin/env python3
"""Detect malformed tool-call signal in recent transcript lines.

Reads JSONL from stdin (typically `tail -n 6` of the active transcript).
Prints "1" if the previous turn shows a malformed tool call, else "0".

Root cause (forensic #12952): streaming stop_sequence truncation (2.1.157+
regression). The leak signature is a stray plaintext token (call/count/course)
immediately before an <invoke> tag, with NO function_calls opening token — the
parser then treats the whole block as text.

Detection is intentionally NARROW to avoid false positives: an assistant text
block that merely *quotes* </invoke> or </parameter> (e.g. this analysis, or
docs about the bug) must NOT trigger. We require the actual leak signature.
"""
import re
import sys
import json

# Leak signature: a bare leftover token (call/count/course) on its own,
# immediately followed by an opening <invoke ...> with no namespaced
# function_calls wrapper. Matches the documented 2.1.157+ truncation remnant.
LEAK_RE = re.compile(r"(?:^|\n)\s*(?:call|count|course)\s*\n\s*<invoke\b")


def main() -> None:
    hit = False
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue

        message = obj.get("message", {})
        content = message.get("content") if isinstance(message, dict) else None

        # Signal 1: the harness echoed the malformed-parse error (authoritative).
        blob = json.dumps(content, ensure_ascii=False) if content is not None else ""
        if "malformed and could not be parsed" in blob:
            hit = True

        # Signal 2: an assistant text block carries the actual leak signature.
        # NOT mere presence of </invoke> — that fires on legitimate quoting.
        if obj.get("type") == "assistant" and isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    if LEAK_RE.search(text):
                        hit = True

    print("1" if hit else "0")


if __name__ == "__main__":
    main()
