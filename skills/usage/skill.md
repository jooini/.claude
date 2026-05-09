---
name: usage
description: LLM 사용량 종합 리포트. /usage 로 Claude Code + Codex(GPT) + Ollama 누적 토큰/세션/호출 횟수와 일별 추이를 한 번에 본다. /usage 30 으로 N일 윈도우 변경.
---

# /usage — LLM Usage Report

여러 LLM을 병렬로 쓰는 워크플로우에서 **어디에 얼마나 썼는지** 한 번에 본다.

## 데이터 가용성

| LLM | 가용성 | 출처 |
|---|---|---|
| Claude Code | ✅ 완전 | `~/.claude/projects/**/*.jsonl` (`message.usage`) |
| Codex / GPT | ✅ 완전 | `~/.codex/state_5.sqlite` (`threads.tokens_used`) |
| Ollama | ⚠️ 부분 | `~/.claude/cache/gemma-calls.jsonl` |
| Gemini CLI | ❌ 추적 불가 | CLI가 토큰 메타 저장 안 함 |
| GPT 직접 | ❌ 인증 없음 | Codex가 곧 GPT 사용량 |

## 사용

```bash
python3 ~/.claude/scripts/llm-usage.py            # 기본 (14일)
python3 ~/.claude/scripts/llm-usage.py --days 30  # 30일
python3 ~/.claude/scripts/llm-usage.py --json     # 대시보드용 JSON
```

## 출력 예시

- **누적**: Claude Code 31.7B 토큰 / Codex 994M 토큰
- **모델별**: gpt-5.4 234세션 668M, gpt-5.3-codex 23세션 242M 등
- **일별 추이**: 최근 N일 Claude턴/토큰, Codex세션/토큰, Ollama호출

## 규칙

- Claude Code 토큰은 cache_read 포함 — 실제 청구 토큰과 다를 수 있음
- Codex tokens_used는 OpenAI 청구 토큰과 일치 (CLI가 직접 기록)
- `--json`은 대시보드 패널이 사용
- Gemini는 CLI 한계로 추적 불가 — 별도 도구 필요 시 재검토
