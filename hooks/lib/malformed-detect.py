#!/usr/bin/env python3
"""Detect malformed tool-call signal in recent transcript lines.

Reads JSONL from stdin (typically `tail -n 6` of the active transcript).
Prints "1" if the previous turn shows a malformed tool call, else "0".
"""
import sys
import json


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
        blob = json.dumps(content, ensure_ascii=False) if content is not None else ""

        if "malformed and could not be parsed" in blob:
            hit = True

        if obj.get("type") == "assistant" and isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    if "</invoke>" in text or "</parameter>" in text:
                        hit = True

    print("1" if hit else "0")


if __name__ == "__main__":
    main()
