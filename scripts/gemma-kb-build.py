#!/usr/bin/env python3
"""
모든 Workspace 프로젝트 순회 → 핵심 파일(README, package.json, pyproject, composer 등) 수집 →
Gemma에 넘겨 '이 프로젝트는 뭘 하는 곳' 한 줄 + 주요 스택 + 언어 요약 생성.
결과: ~/.claude/cache/project-kb/{프로젝트명}.md
"""
import json
import os
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
WORKSPACE = Path.home() / "Workspace"
OUT_DIR = Path.home() / ".claude" / "cache" / "project-kb"
OUT_DIR.mkdir(parents=True, exist_ok=True)

LOG = OUT_DIR / "_build.log"
MANIFEST = OUT_DIR / "_manifest.json"

CANDIDATE_FILES = [
    "README.md", "README.rst", "README.txt",
    "package.json", "pyproject.toml", "composer.json",
    "build.gradle", "build.gradle.kts", "pom.xml",
    "Cargo.toml", "go.mod", "Gemfile",
    "CLAUDE.md", ".claude/CLAUDE.md",
    "docker-compose.yml", "compose.yml",
]

def log(msg):
    ts = time.strftime("%H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")

def collect_evidence(proj_dir: Path) -> str:
    """프로젝트에서 핵심 파일 내용 수집 (각 파일 최대 60줄)."""
    parts = []

    # 디렉토리 트리 (깊이 2, 최대 30줄)
    try:
        result = subprocess.run(
            ["find", str(proj_dir), "-maxdepth", "2", "-not", "-path", "*/.*", "-not", "-path", "*/node_modules*"],
            capture_output=True, text=True, timeout=5
        )
        tree_lines = result.stdout.strip().split("\n")[:30]
        # proj_dir 부분 제거해서 상대경로로
        rel = [l.replace(str(proj_dir) + "/", "") for l in tree_lines if l.strip()]
        if rel:
            parts.append(f"## 디렉토리 구조\n{chr(10).join(rel)}")
    except Exception:
        pass

    # 후보 파일 내용
    for name in CANDIDATE_FILES:
        fp = proj_dir / name
        if not fp.exists() or not fp.is_file():
            continue
        try:
            content = fp.read_text(encoding="utf-8", errors="replace")
            lines = content.split("\n")[:60]
            body = "\n".join(lines)
            if body.strip():
                parts.append(f"## {name}\n```\n{body}\n```")
        except Exception:
            pass

    return "\n\n".join(parts)[:8000]

def gemma_summarize(proj_name: str, evidence: str) -> str:
    prompt = f"""다음은 '{proj_name}' 프로젝트의 핵심 파일들이다. 한국어로 분석해서 구조화된 요약을 작성해줘.

출력 형식 (정확히):

# {proj_name}

## 한 줄 설명
<이 프로젝트가 뭘 하는 곳인지 70자 이내>

## 스택
- 언어: <Python / TypeScript / Kotlin / Go / PHP / ...>
- 프레임워크: <FastAPI / Next.js / Spring Boot / Laravel / ...>
- DB/인프라: <PostgreSQL / Redis / Docker / ...> (없으면 "없음")

## 주요 디렉토리
- <경로> — <용도 한 줄>

## 엔트리 포인트
- <주요 실행 파일/모듈>

## 외부 의존성
- <중요 의존 서비스/API, 없으면 "없음">

규칙:
- README와 의존성 파일, 디렉토리 구조만 근거로 작성. 추측 금지.
- 불명인 항목은 "불명"이라고 명시.
- 이모지/장식 금지.
- 존재하지 않는 파일/경로 추측 금지.

증거:
{evidence}
"""
    body = json.dumps({
        "model": "gemma4:e4b",
        "messages": [
            {"role": "system", "content": "한국어로 구조화된 프로젝트 요약만 출력. 인사/설명 금지."},
            {"role": "user", "content": prompt}
        ],
        "stream": False,
        "keep_alive": "30m"
    }).encode()

    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
    return data.get("message", {}).get("content", "")

def main():
    # Ollama 연결 확인
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        with urllib.request.urlopen(req, timeout=3) as r:
            r.read()
    except Exception as e:
        log(f"ERR: Ollama 접근 불가 — {e}")
        sys.exit(1)

    log(f"시작 — Ollama {OLLAMA}, 출력 {OUT_DIR}")

    # 프로젝트 수집
    projects = []
    for p in sorted(WORKSPACE.iterdir()):
        if not p.is_dir():
            continue
        if not (p / ".git").exists():
            continue
        projects.append(p)
    log(f"프로젝트 {len(projects)}개 발견")

    manifest = {"total": len(projects), "started": time.time(), "items": {}}
    success = 0
    skipped = 0
    failed = 0

    for i, proj in enumerate(projects, 1):
        name = proj.name
        out_file = OUT_DIR / f"{name}.md"

        # 이미 있고 1주일 이내면 스킵
        if out_file.exists():
            age = time.time() - out_file.stat().st_mtime
            if age < 7 * 86400:
                skipped += 1
                log(f"[{i}/{len(projects)}] {name} — 캐시 사용 (나이 {int(age/3600)}h)")
                manifest["items"][name] = {"status": "cached", "path": str(out_file)}
                continue

        log(f"[{i}/{len(projects)}] {name} — 증거 수집 중...")
        evidence = collect_evidence(proj)

        if not evidence.strip():
            log(f"  → 증거 없음 (빈 프로젝트?) 스킵")
            failed += 1
            manifest["items"][name] = {"status": "no_evidence"}
            continue

        t0 = time.time()
        try:
            result = gemma_summarize(name, evidence)
        except Exception as e:
            log(f"  → Gemma 호출 실패: {e}")
            failed += 1
            manifest["items"][name] = {"status": "error", "error": str(e)}
            continue

        elapsed = time.time() - t0
        if not result.strip():
            log(f"  → 빈 응답")
            failed += 1
            manifest["items"][name] = {"status": "empty_response"}
            continue

        out_file.write_text(result, encoding="utf-8")
        success += 1
        log(f"  ✓ 저장 ({elapsed:.1f}s, {len(result)}자)")
        manifest["items"][name] = {
            "status": "ok",
            "path": str(out_file),
            "elapsed": round(elapsed, 2),
            "bytes": len(result)
        }

        # 중간 저장 (10개마다)
        if i % 10 == 0:
            MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))

    manifest["finished"] = time.time()
    manifest["summary"] = {"success": success, "skipped": skipped, "failed": failed}
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))

    log(f"완료 — 성공 {success} / 캐시 {skipped} / 실패 {failed}")

if __name__ == "__main__":
    main()
