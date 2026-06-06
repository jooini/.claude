#!/usr/bin/env python3
"""Generate an inventory of runtime files that can call LLM tools."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "registry" / "llm-calls-inventory.json"

PROVIDER_PATTERNS: dict[str, list[str]] = {
    "gemini_or_agy": [
        r"\bGEMINI_CLI\b",
        r"\bagy\b",
        r"\bgemini\b",
        r"llm-call\.sh[^\n]*\bgemini\b",
        r"llm-call\.sh[^\n]*\bagy\b",
        r"gemini-wrapped",
        r"ask-gemini",
    ],
    "codex": [
        r"codex exec",
        r"codex:",
        r"ask-codex",
        r"llm-call\.sh[^\n]*\bcodex\b",
    ],
    "ollama": [
        r"\bollama\b",
        r"leonard\.local:11434",
        r"/api/tags",
        r"llm-call\.sh[^\n]*\b(ini|ollama|gemma|qwen)\b",
    ],
    "gemma": [
        r"\bgemma\b",
        r"ask-gemma",
        r"llm-call\.sh[^\n]*\b(gemma|ini)\b",
    ],
    "qwen_ini": [
        r"\bini\b",
        r"qwen",
        r"qwen3",
        r"\.local/bin/ini",
        r"llm-call\.sh[^\n]*\b(ini|qwen)\b",
    ],
}

RUNTIME_GLOBS = [
    "hooks/**/*.sh",
    "scripts/*.sh",
    "scripts/*.py",
]

EXCLUDE_PARTS = {
    "__pycache__",
    "_archive",
    "_disabled",
    "_removed_2026-06-01",
    "_test",
    "dashboard",
}

EXCLUDE_NAMES = {
    "audit-claude-config.py",
    "generate-architecture-diagrams.py",
    "generate-hook-consolidation-candidates.py",
    "generate-hook-consolidation-plan.py",
    "generate-hook-manifest.py",
    "generate-hook-inventory.py",
    "generate-llm-call-inventory.py",
    "project-settings-from-registry.py",
}


def should_skip(path: Path) -> bool:
    return path.name in EXCLUDE_NAMES or any(part in EXCLUDE_PARTS for part in path.parts)


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def runtime_files() -> list[Path]:
    files: set[Path] = set()
    for pattern in RUNTIME_GLOBS:
        for path in ROOT.glob(pattern):
            if path.is_file() and not should_skip(path):
                files.add(path)
    return sorted(files)


def scan_file(path: Path) -> dict[str, Any] | None:
    text = path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()
    hits = []
    providers = []

    for provider, patterns in PROVIDER_PATTERNS.items():
        provider_hits = []
        for line_number, line in enumerate(lines, start=1):
            for pattern in patterns:
                if re.search(pattern, line, re.IGNORECASE):
                    provider_hits.append(
                        {
                            "line": line_number,
                            "pattern": pattern,
                            "text": line.strip()[:160],
                        }
                    )
                    break
        if provider_hits:
            providers.append(provider)
            hits.append({"provider": provider, "hits": provider_hits[:20]})

    if not hits:
        return None

    return {
        "path": relative(path),
        "providers": providers,
        "hit_count": sum(len(item["hits"]) for item in hits),
        "hits": hits,
    }


def generate_inventory() -> dict[str, Any]:
    entries = [entry for path in runtime_files() if (entry := scan_file(path))]
    provider_counts = []
    for provider in PROVIDER_PATTERNS:
        provider_counts.append(
            {
                "provider": provider,
                "file_count": sum(1 for entry in entries if provider in entry["providers"]),
            }
        )
    return {
        "version": 1,
        "generated_from": RUNTIME_GLOBS,
        "file_count": len(entries),
        "provider_counts": provider_counts,
        "entries": entries,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    inventory = generate_inventory()
    rendered = json.dumps(inventory, ensure_ascii=False, indent=2) + "\n"
    if args.write:
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
