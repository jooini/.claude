#!/usr/bin/env python3
"""
재시도 v2 — Gemma 자체 진단 기반 개선:

변경점:
1. format=json 모드 제거 → 자유 텍스트로 필드별 요청 후 수동 파싱
2. 입력 길이 축소: 5000자 → 2500자 (첫 부분 + 중간 발췌)
3. 프롬프트 분해: 요약→구조화 2단계 대신, 필드별로 간단히 한 방에
4. num_predict: 600 → 400 (생성량 컷)
5. 단일 문서만 처리 (batch 아님, 각 호출 독립)
6. 각 요청마다 잠깐 sleep (KV cache 압박 방지)
"""
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
KB_ROOT = Path.home() / ".claude" / "agents" / "knowledge"
OUT_DIR = Path.home() / ".claude" / "cache" / "knowledge-index"
OUT_DIR.mkdir(parents=True, exist_ok=True)
INDEX_FILE = Path.home() / ".claude" / "cache" / "knowledge-index.json"
LOG_FILE = OUT_DIR / "_retry_v2.log"

SKIP_FILES = {"knowledge-catalog.md", "MAINTENANCE.md", ".DS_Store"}
SKIP_DIRS = {"projects"}
MAX_ATTEMPTS = 3


def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def collect_all_files():
    files = []
    for role_dir in sorted(KB_ROOT.iterdir()):
        if not role_dir.is_dir() or role_dir.name in SKIP_DIRS:
            continue
        for md in sorted(role_dir.rglob("*.md")):
            if md.name in SKIP_FILES:
                continue
            files.append(md)
    return files


def needs_retry(rel: str, entry) -> bool:
    if entry is None:
        return True
    if not entry.get("summary") or not entry.get("title"):
        return True
    if not entry.get("keywords"):
        return True
    return False


def smart_trim(content: str, max_chars: int = 1200) -> str:
    """문서 앞부분 + 중간 발췌. 토큰 버짓 빡빡하니 1200자 제한."""
    if len(content) <= max_chars:
        return content
    head = content[:max_chars - 200]
    middle_pos = len(content) // 2
    middle = content[middle_pos:middle_pos + 200]
    return f"{head}\n\n...\n\n{middle}"


def gemma_call(messages, num_predict=400, temperature=0.2, timeout=45):
    body = json.dumps({
        "model": "gemma4:e4b",
        "messages": messages,
        "stream": False,
        "keep_alive": "30m",
        "options": {
            "num_predict": num_predict,
            "temperature": temperature,
            "top_k": 40,
            "top_p": 0.9
        }
    }).encode()
    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read())
    return data.get("message", {}).get("content", "").strip()


def try_structured_text(path: Path, content: str) -> dict:
    """format=json 없이 정해진 텍스트 형식으로 응답 요청. 최소 프롬프트로 토큰 절약."""
    rel = path.relative_to(KB_ROOT)
    body = smart_trim(content, 1200)

    prompt = f"""다음 문서 요약.

파일: {rel}
내용:
{body}

형식 (정확히 5줄, 접두어 그대로):
제목:
요약:
주제: A / B / C / D / E
키워드: k1, k2, k3, k4, k5
적용: """

    messages = [
        {"role": "user", "content": prompt}
    ]

    raw = gemma_call(messages, num_predict=800, temperature=0.3)
    if not raw:
        raise ValueError("빈 응답")

    result = {
        "title": "",
        "summary": "",
        "topics": [],
        "keywords": [],
        "applies_when": ""
    }

    for line in raw.split("\n"):
        line = line.strip()
        if not line:
            continue
        # 볼드/이모지 제거
        line = re.sub(r"^\*+\s*|\s*\*+$", "", line)
        if line.startswith("제목:") or line.startswith("제목："):
            result["title"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
        elif line.startswith("요약:") or line.startswith("요약："):
            result["summary"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
        elif line.startswith("주제:") or line.startswith("주제："):
            topics_raw = line.split(":", 1)[-1].split("：", 1)[-1]
            result["topics"] = [t.strip() for t in re.split(r"[/,、]", topics_raw) if t.strip()]
        elif line.startswith("키워드:") or line.startswith("키워드："):
            kw_raw = line.split(":", 1)[-1].split("：", 1)[-1]
            result["keywords"] = [t.strip() for t in re.split(r"[,、/]", kw_raw) if t.strip()]
        elif line.startswith("적용:") or line.startswith("적용："):
            result["applies_when"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()

    # 접두어 무시하고 자유 텍스트로 응답한 경우 — 첫 줄을 제목, 나머지를 요약으로
    if not result["title"] or not result["summary"]:
        lines = [l.strip() for l in raw.split("\n") if l.strip()]
        lines = [re.sub(r"^\*+\s*|\s*\*+$", "", l) for l in lines]
        if lines:
            # 제목: 첫 문장 (70자까지)
            if not result["title"]:
                first = lines[0][:70].rstrip("**").strip()
                result["title"] = first if first else path.stem
            # 요약: 나머지 이어붙이기
            if not result["summary"]:
                rest = " ".join(lines[1:] if len(lines) > 1 else lines)[:300]
                result["summary"] = rest if rest else result["title"]

    if not result["title"] or not result["summary"]:
        raise ValueError(f"필수 필드 파싱 실패 (raw 앞 200: {raw[:200]})")

    return result


def try_minimal(path: Path, content: str) -> dict:
    """최소 프롬프트 — 제목/요약만 (실패 시 최후 수단)."""
    rel = path.relative_to(KB_ROOT)
    body = smart_trim(content, 600)

    prompt = f"""문서 요약.

파일: {rel}
{body}

형식 (2줄):
제목:
요약: """
    messages = [
        {"role": "user", "content": prompt}
    ]
    raw = gemma_call(messages, num_predict=300, temperature=0.4)
    if not raw:
        raise ValueError("빈 응답")

    result = {"title": "", "summary": "", "topics": [], "keywords": [], "applies_when": ""}
    for line in raw.split("\n"):
        line = line.strip()
        line = re.sub(r"^\*+\s*|\s*\*+$", "", line)
        if line.startswith("제목:") or line.startswith("제목："):
            result["title"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
        elif line.startswith("요약:") or line.startswith("요약："):
            result["summary"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()

    if not result["title"]:
        # 제목 파싱 실패 시 파일명을 제목으로
        result["title"] = path.stem

    if not result["summary"]:
        raise ValueError(f"최소 요약 실패 (raw: {raw[:150]})")

    return result


def summarize_with_fallback(path: Path, content: str):
    """구조화 → 최소 순으로 시도."""
    errors = []
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            if attempt <= 2:
                return try_structured_text(path, content)
            else:
                # 최후 수단
                return try_minimal(path, content)
        except Exception as e:
            errors.append(f"att{attempt}: {e}")
            time.sleep(2)  # KV cache 압박 방지
    raise RuntimeError(f"{MAX_ATTEMPTS}회 실패 — {' / '.join(errors[-2:])}")


def save_individual(rel: str, entry: dict):
    slug = rel.replace("/", "_")
    (OUT_DIR / f"{slug}.md").write_text(
        f"# {entry['title']}\n\n"
        f"**경로**: `{rel}`\n"
        f"**역할**: {entry.get('role', '')}\n\n"
        f"## 요약\n{entry['summary']}\n\n"
        f"## 주제\n" + "\n".join(f"- {t}" for t in entry.get("topics", [])) + "\n\n"
        f"## 키워드\n" + ", ".join(entry.get("keywords", [])) + "\n\n"
        f"## 사용 시점\n{entry.get('applies_when', '')}\n",
        encoding="utf-8"
    )


def main():
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        with urllib.request.urlopen(req, timeout=3) as r:
            r.read()
    except Exception as e:
        log(f"ERR: Ollama 접근 불가 — {e}")
        return 1

    index = {}
    if INDEX_FILE.exists():
        try:
            index = json.loads(INDEX_FILE.read_text())
        except Exception:
            pass

    all_files = collect_all_files()
    log(f"전체 {len(all_files)}개 · 인덱스 {len(index)}개")

    todo = [p for p in all_files if needs_retry(str(p.relative_to(KB_ROOT)), index.get(str(p.relative_to(KB_ROOT))))]
    if not todo:
        log("재시도 대상 없음")
        return 0

    log(f"재시도 v2 대상: {len(todo)}개")

    success = 0
    still_failed = []

    for i, path in enumerate(todo, 1):
        rel = str(path.relative_to(KB_ROOT))
        role = path.parent.name if path.parent.parent == KB_ROOT else path.parent.parent.name

        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            log(f"[{i}/{len(todo)}] {rel} — 읽기 실패: {e}")
            still_failed.append((rel, str(e)))
            continue

        t0 = time.time()
        try:
            summary = summarize_with_fallback(path, content)
        except Exception as e:
            log(f"[{i}/{len(todo)}] {rel} — 최종 실패: {e}")
            still_failed.append((rel, str(e)))
            time.sleep(1)
            continue

        entry = {
            "path": rel,
            "role": role,
            "mtime": path.stat().st_mtime,
            "bytes": len(content),
            "title": summary.get("title", ""),
            "summary": summary.get("summary", ""),
            "topics": summary.get("topics", []),
            "keywords": summary.get("keywords", []),
            "applies_when": summary.get("applies_when", ""),
            "indexed_at": time.time(),
            "retry_v2": True
        }
        index[rel] = entry
        save_individual(rel, entry)
        success += 1
        elapsed = time.time() - t0
        log(f"[{i}/{len(todo)}] {rel} — ✓ ({elapsed:.1f}s)")

        # KV cache 압박 방지
        time.sleep(0.3)

        if i % 10 == 0:
            INDEX_FILE.write_text(json.dumps(index, ensure_ascii=False, indent=2))
            log(f"  중간 저장 — 성공 {success}, 실패 {len(still_failed)}")

    INDEX_FILE.write_text(json.dumps(index, ensure_ascii=False, indent=2))

    log(f"재시도 v2 완료 — 성공 {success} / 실패 {len(still_failed)}")
    if still_failed:
        (OUT_DIR / "_final_failures_v2.json").write_text(
            json.dumps(still_failed, ensure_ascii=False, indent=2)
        )
        log(f"실패 목록: {OUT_DIR / '_final_failures_v2.json'}")

    return 0 if len(still_failed) == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
