#!/usr/bin/env python3
"""
~/.claude/agents/knowledge/ 의 모든 md 파일을 Gemma로 요약해 인덱스 생성.
결과: ~/.claude/cache/knowledge-index.json (단일 파일, 검색 가능)
      ~/.claude/cache/knowledge-index/{role}_{file}.md (개별 요약)
"""
import json
import os
import time
import urllib.request
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
KB_ROOT = Path.home() / ".claude" / "agents" / "knowledge"
OUT_DIR = Path.home() / ".claude" / "cache" / "knowledge-index"
OUT_DIR.mkdir(parents=True, exist_ok=True)

INDEX_FILE = Path.home() / ".claude" / "cache" / "knowledge-index.json"
LOG_FILE = OUT_DIR / "_build.log"

SKIP_FILES = {"knowledge-catalog.md", "MAINTENANCE.md", ".DS_Store"}
SKIP_DIRS = {"projects"}  # 회사 전용 제외

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")

def collect_files():
    files = []
    for role_dir in sorted(KB_ROOT.iterdir()):
        if not role_dir.is_dir():
            continue
        if role_dir.name in SKIP_DIRS:
            continue
        for md in sorted(role_dir.rglob("*.md")):
            if md.name in SKIP_FILES:
                continue
            files.append(md)
    return files

def gemma_summarize(path: Path, content: str) -> dict:
    rel = path.relative_to(KB_ROOT)
    body_trimmed = content[:6000]

    prompt = f"""다음 Knowledge 문서를 한국어로 요약해줘. 검색 인덱스용이니 정확한 키워드가 중요하다.

출력 형식 (정확히 이 JSON — 코드 블록 없이, 다른 텍스트 없이 JSON만):

{{
  "title": "<문서 제목 한 줄>",
  "summary": "<이 문서가 다루는 내용 2줄 요약>",
  "topics": ["<다루는 주제 1>", "<주제 2>", "<주제 3>", "<주제 4>", "<주제 5>"],
  "keywords": ["<검색용 키워드 1>", "<키워드 2>", "..."],
  "applies_when": "<어떤 상황에서 이 문서를 참고하는지 한 줄>"
}}

규칙:
- JSON만 출력. 설명/코드블록/마크다운 절대 금지.
- keywords는 10개 이내, 구체적이고 검색에 유용한 단어.
- 없는 내용 추측 금지.

파일 경로: {rel}

문서 내용:
{body_trimmed}
"""

    body = json.dumps({
        "model": "gemma4:e4b",
        "messages": [
            {"role": "system", "content": "JSON만 출력. 설명/인사/코드블록 금지."},
            {"role": "user", "content": prompt}
        ],
        "stream": False,
        "keep_alive": "30m",
        "format": "json",
        "options": {"num_predict": 500}
    }).encode()

    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())

    raw = data.get("message", {}).get("content", "").strip()
    # JSON 파싱
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        # 코드블록 제거 재시도
        if raw.startswith("```"):
            raw = raw.strip("`").lstrip("json").strip()
        parsed = json.loads(raw)
    return parsed

def main():
    # Ollama 확인
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        with urllib.request.urlopen(req, timeout=3) as r:
            r.read()
    except Exception as e:
        log(f"ERR: Ollama 접근 불가 — {e}")
        return 1

    files = collect_files()
    log(f"시작 — {len(files)}개 문서 인덱싱")

    # 기존 인덱스 로드 (증분 갱신용)
    index = {}
    if INDEX_FILE.exists():
        try:
            index = json.loads(INDEX_FILE.read_text())
        except Exception:
            index = {}

    success = 0
    cached = 0
    failed = 0

    for i, path in enumerate(files, 1):
        rel = str(path.relative_to(KB_ROOT))
        role = path.parent.name if path.parent.parent == KB_ROOT else path.parent.parent.name
        mtime = path.stat().st_mtime

        # 이미 인덱싱됐고 파일 mtime 변화 없으면 스킵
        if rel in index and index[rel].get("mtime") == mtime:
            cached += 1
            log(f"[{i}/{len(files)}] {rel} — 캐시 사용")
            continue

        content = path.read_text(encoding="utf-8", errors="replace")
        t0 = time.time()
        try:
            summary = gemma_summarize(path, content)
        except Exception as e:
            log(f"[{i}/{len(files)}] {rel} — 실패: {e}")
            failed += 1
            continue

        entry = {
            "path": rel,
            "role": role,
            "mtime": mtime,
            "bytes": len(content),
            "title": summary.get("title", ""),
            "summary": summary.get("summary", ""),
            "topics": summary.get("topics", []),
            "keywords": summary.get("keywords", []),
            "applies_when": summary.get("applies_when", ""),
            "indexed_at": time.time()
        }
        index[rel] = entry

        # 개별 요약 파일도 저장
        slug = rel.replace("/", "_")
        (OUT_DIR / f"{slug}.md").write_text(
            f"# {entry['title']}\n\n"
            f"**경로**: `{rel}`\n"
            f"**역할**: {role}\n\n"
            f"## 요약\n{entry['summary']}\n\n"
            f"## 주제\n" + "\n".join(f"- {t}" for t in entry["topics"]) + "\n\n"
            f"## 키워드\n" + ", ".join(entry["keywords"]) + "\n\n"
            f"## 사용 시점\n{entry['applies_when']}\n",
            encoding="utf-8"
        )

        elapsed = time.time() - t0
        success += 1
        log(f"[{i}/{len(files)}] {rel} — ✓ ({elapsed:.1f}s)")

        # 20개마다 인덱스 중간 저장
        if i % 20 == 0:
            INDEX_FILE.write_text(json.dumps(index, ensure_ascii=False, indent=2))

    INDEX_FILE.write_text(json.dumps(index, ensure_ascii=False, indent=2))
    log(f"완료 — 신규 {success} / 캐시 {cached} / 실패 {failed}")
    log(f"인덱스: {INDEX_FILE}")
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(main())
