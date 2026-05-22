---
name: usage
description: LLM 사용량 종합 리포트. /usage 로 Claude Code + Codex(GPT) + Gemini + Ollama 누적 토큰/세션/호출/비용과 일별 추이를 한 번에 본다. /usage 30 으로 N일 윈도우 변경.
---

# /usage — LLM Usage Report

여러 LLM을 병렬로 쓰는 워크플로우에서 **어디에 얼마나 썼는지** 한 번에 본다.

## 데이터 가용성

| LLM | 가용성 | 출처 |
|---|---|---|
| Claude Code | ✅ 완전 | `~/.claude/projects/**/*.jsonl` (`message.usage`) |
| Codex / GPT | ✅ 완전 | `~/.codex/state_5.sqlite` (`threads.tokens_used`) |
| Gemini CLI | ✅ 완전 | `~/.claude/cache/gemini-telemetry.jsonl` (`gemini_cli.api_response`) — `~/.gemini/settings.json`의 `telemetry.enabled: true` 필요. **2026-06-18부터 무료/Pro/Ultra deprecated** |
| Antigravity (agy) | ⚠️ 부분 | `~/.claude/cache/agy-calls.jsonl` (wrapper 호출만, duration/exit_code) + `~/.gemini/antigravity-cli/log/cli-*.log` (Antigravity 로그인 시 텔레메트리). agy는 `--output-format stream-json` 미지원으로 토큰 메타 추출 불가 |
| Ollama | ⚠️ 부분 | `~/.claude/cache/gemma-calls.jsonl` |
| GPT 직접 | ❌ 인증 없음 | Codex가 곧 GPT 사용량 |

## 사용

```bash
python3 ~/.claude/scripts/llm-usage.py            # 기본 (14일)
python3 ~/.claude/scripts/llm-usage.py --days 30  # 30일
python3 ~/.claude/scripts/llm-usage.py --json     # 대시보드용 JSON
```

## 출력 예시

- **누적**: Claude Code 39B 토큰 / Codex 1.04B 토큰 / Gemini 2.1M 토큰
- **모델별**: gpt-5.4 234세션 668M, gemini-3-flash-preview 77회 1.88M 등
- **일별 추이**: 최근 N일 Claude턴/비용, Codex세션/비용, Gemini비용, 합계

## 규칙

- Claude Code 토큰은 cache_read 포함 — 실제 청구 토큰과 다를 수 있음
- Codex tokens_used는 OpenAI 청구 토큰과 일치 (CLI가 직접 기록)
- Gemini는 telemetry 파일이 진실. 옵션 wrapper(`gemini-wrapped.sh`)는 caller 식별용 — telemetry와 중복 카운트 주의
- agy는 wrapper jsonl이 유일한 caller 추적 수단 (stream-json 미지원). 토큰 추적 불가 — 호출 횟수/시간만 기록됨
- `--json`은 대시보드 패널이 사용
