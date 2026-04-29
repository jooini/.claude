#!/usr/bin/env python3
"""
퍼즐 풀이 — 버그 증상을 Gemma에 넘겨 가설 3개 + 검증 명령 생성.

사용:
  ./gemma-puzzle.py "로그인 실패, 500 에러"
  ./gemma-puzzle.py < error.log    # stdin 파이프
  ./gemma-puzzle.py --run "버그 설명"   # 검증 명령 자동 실행까지

출력: 가설별 {가설/검증명령/예상결과}
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")


def log(msg):
    print(msg, flush=True)


def call_gemma(prompt: str, num_predict: int = 1500) -> str:
    body = json.dumps({
        "model": "gemma4:e4b",
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "keep_alive": "30m",
        "options": {"num_predict": num_predict, "temperature": 0.4}
    }).encode()
    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read()).get("message", {}).get("content", "")


def generate_hypotheses(symptom: str, context: str = "") -> str:
    prompt = f"""다음 버그 증상에 대한 가설 3개를 생성해라.

증상:
{symptom}

추가 맥락 (있으면):
{context if context else "(없음)"}

출력 형식 (정확히 이 구조, 한국어):

## 가설 1
원인: <가능한 원인 한 줄>
검증명령: <재현/확인용 Bash 명령 한 줄 — 실제 실행 가능해야 함>
예상결과: <가설이 맞으면 나올 결과 한 줄>

## 가설 2
원인: ...
검증명령: ...
예상결과: ...

## 가설 3
원인: ...
검증명령: ...
예상결과: ...

규칙:
- 검증명령은 읽기 전용 (`curl`, `grep`, `ls`, `cat`, `git log`, `ps`, `systemctl status`). 파괴적 명령 금지.
- 근거 없는 추측 금지. 증상에 나온 키워드 기반.
- 이모지/장식 금지.
"""
    return call_gemma(prompt, num_predict=1500)


def parse_hypotheses(text: str) -> list:
    """가설 블록 파싱."""
    blocks = re.split(r"^## 가설 \d+", text, flags=re.MULTILINE)[1:]  # 첫 번째는 header 이전
    parsed = []
    for i, block in enumerate(blocks[:3], 1):
        h = {"num": i, "cause": "", "command": "", "expected": ""}
        for line in block.strip().split("\n"):
            line = line.strip()
            if line.startswith("원인:") or line.startswith("원인：") :
                h["cause"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
            elif line.startswith("검증명령:") or line.startswith("검증명령：") :
                h["command"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
                # 백틱 제거
                h["command"] = h["command"].strip("`")
            elif line.startswith("예상결과:") or line.startswith("예상결과：") :
                h["expected"] = line.split(":", 1)[-1].split("：", 1)[-1].strip()
        parsed.append(h)
    return parsed


def is_safe_command(cmd: str) -> bool:
    """검증 명령 안전성 검사 — 읽기 전용만 허용."""
    cmd_lower = cmd.lower()
    # 위험 패턴
    dangerous = [
        "rm ", "mv ", "cp ", ">", ">>", "|sh", "| sh", "|bash", "| bash",
        "sudo", "kill", "chmod", "chown", "dd ", "mkfs", "curl -x",
        "git push", "git reset --hard", "git checkout -", "docker rm", "docker kill",
        "drop ", "delete from", "truncate", "update ",
    ]
    for pattern in dangerous:
        if pattern in cmd_lower:
            return False
    # 안전 커맨드로 시작하는지
    safe_starters = ["curl", "grep", "ls", "cat", "head", "tail", "git log", "git status",
                      "git diff", "git show", "git branch", "ps", "lsof", "netstat",
                      "docker ps", "docker logs", "systemctl status", "launchctl list",
                      "find", "wc", "echo", "which", "env", "printenv", "du", "df"]
    cmd_clean = cmd.lstrip("!").strip()
    return any(cmd_clean.startswith(s) for s in safe_starters)


def run_command(cmd: str, timeout: int = 15) -> dict:
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, env=os.environ
        )
        return {
            "exit_code": result.returncode,
            "stdout": result.stdout[:500],
            "stderr": result.stderr[:500],
        }
    except subprocess.TimeoutExpired:
        return {"exit_code": -1, "stdout": "", "stderr": "[timeout]"}
    except Exception as e:
        return {"exit_code": -2, "stdout": "", "stderr": str(e)[:200]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("symptom", nargs="*", help="버그 증상 설명")
    parser.add_argument("--run", action="store_true", help="가설별 검증 명령 자동 실행 (읽기 전용만)")
    parser.add_argument("--context", default="", help="추가 맥락")
    args = parser.parse_args()

    # stdin 입력 지원
    symptom_parts = args.symptom[:]
    if not sys.stdin.isatty():
        stdin_text = sys.stdin.read().strip()
        if stdin_text:
            symptom_parts.append(stdin_text)
    symptom = " ".join(symptom_parts)

    if not symptom:
        print("사용법: ./gemma-puzzle.py \"버그 증상\" [--run]", file=sys.stderr)
        return 1

    # Ollama 확인
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        urllib.request.urlopen(req, timeout=3).read()
    except Exception as e:
        log(f"ERR: Ollama 접근 불가 — {e}")
        return 1

    log(f"=== 퍼즐 풀이 ===")
    log(f"증상: {symptom[:150]}{'...' if len(symptom) > 150 else ''}")
    log("")
    log("Gemma가 가설 생성 중 (10~20초)...")
    t0 = time.time()
    raw = generate_hypotheses(symptom, args.context)
    log(f"  완료 ({time.time()-t0:.1f}초)")
    log("")

    hypotheses = parse_hypotheses(raw)
    if not hypotheses:
        log("⚠️ 가설 파싱 실패. Gemma 원 응답:")
        log(raw)
        return 2

    log(f"=== 가설 {len(hypotheses)}개 생성됨 ===\n")

    for h in hypotheses:
        log(f"## 가설 {h['num']}: {h['cause']}")
        log(f"   검증명령: {h['command']}")
        log(f"   예상결과: {h['expected']}")

        if args.run and h["command"]:
            if not is_safe_command(h["command"]):
                log(f"   ⚠️ 안전하지 않은 명령 — 자동 실행 스킵")
            else:
                log(f"   [실행 중...]")
                result = run_command(h["command"])
                log(f"   exit={result['exit_code']}")
                if result["stdout"]:
                    log(f"   stdout: {result['stdout'][:200]}")
                if result["stderr"]:
                    log(f"   stderr: {result['stderr'][:200]}")
        log("")

    log("---")
    log("다음 단계:")
    log("- 가설별 결과 보고 가장 유력한 것 선택")
    log("- Claude가 수정 방향 결정")
    log("- 추가 맥락 필요시 --context 옵션 사용")

    return 0


if __name__ == "__main__":
    sys.exit(main())
