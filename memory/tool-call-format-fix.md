---
name: tool-call-format-fix
description: invoke/malformed 도구 호출 에러의 진짜 원인 — CLAUDE.md 강박 룰이 역효과. 룰로 억제하지 말 것
metadata:
  type: feedback
---

도구 호출 `malformed`/`invoke 접두사 누락` 에러가 반복될 때, **CLAUDE.md나 메모리에 "antml 접두사 절대 누락 금지" 같은 HARD 룰을 박는 것은 역효과다.** 최신 Claude Code(2.1.x)는 도구 호출 형식을 자동 처리하므로 모델이 `antml:` 접두사를 의식할 필요가 없는데, 룰이 매 세션 `invoke`/`parameter` 토큰을 반복 강조하면 모델이 평소 안 하던 raw 태그 출력을 의식하게 되어 **자기충족적으로 형식이 깨진다.**

**진짜 점검 순서:**
1. `~/.local/bin/claude --version` 으로 native 설치 버전 확인 (최신인지)
2. `ls ~/.nvm/versions/node/*/bin/claude` 로 묵은 npm 글로벌 구버전 잔존 확인 → 있으면 `npm uninstall -g @anthropic-ai/claude-code`. 구버전이 PATH에서 먼저 잡히면 최신 모델 출력과 파서가 안 맞아 malformed 발생 가능
3. `zsh -lc 'which claude'` 로 실제 활성 바이너리가 native 최신인지 확인

**Why:** 2026-05-30 진단 결과, invoke 에러의 원인은 접두사 룰 부재가 아니라 ① 구버전 nvm claude(2.1.20)와 native(2.1.158) 이중 설치 ② CLAUDE.md `[HARD] 도구 호출 형식` 섹션 자체의 역효과였다. 룰을 삭제하고 구버전을 제거하는 것으로 정리. 기존 메모리(증상을 룰로 억제)는 오진이었다.

**How to apply:** 도구 호출 에러는 룰 추가가 아니라 **버전/설치 환경**부터 본다. 본문에 invoke/parameter 단어를 금지하는 식의 메타-룰은 만들지 말 것 — 정상 버전에선 형식이 자동 처리된다. 관련 환경 이슈는 [[claude-mem-uvx-path-fix]] 류와 함께 점검.
