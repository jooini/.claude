# 참고 — Claude Code 알려진 버그 & 회피책

> 룰의 **근거**. CLAUDE.md 본문에서 분리 (장문이라 본문 가독성 해침). 룰 자체는 CLAUDE.md에 남기고, 여기는 "왜" 만 보관.

## 1. malformed tool_use — Opus 4.8 모델 레이어 회귀

**증상**: `Your tool call was malformed and could not be parsed`

**진짜 원인 (2026-06-02 재귀속 — 공식 이슈트래커 + 2.1.160 바이너리 실측으로 기존 진단 반증)**

malformed 의 근본 원인은 **Opus 4.8 모델 레이어의 tool_use 생성 회귀**다.

⚠️ 과거 "streaming `stop_sequence` truncation — 2.1.157+ 클라이언트 회귀" 설명은 **틀렸다(반증)**:
- GitHub #63604 / #64076 이 **2.1.156(회귀 전 버전)에서도 재현** → 클라 버전 회귀가 아님
- 모든 malformed 이슈가 `area:model` / `api:anthropic` 라벨
- **Opus 4.8 특정** — 같은 세션·버전에서 4.7 / Sonnet 4.6 은 깨끗

**메커니즘**: 모델이 tool_use XML 생성 중 꼬리 토큰(`call` / `count` / `court`)이 평문으로 누출 → `<invoke>` 앞에 굳음 → 파서가 text 처리 → malformed.

**실측**:
- 빈도 ~3.1~4%
- 최고위험: 1M context + `effortLevel:xhigh` (#64235 / #64150)
- 재시도 시 대개 성공 (비결정적)

**효과 없는 레버 (확인됨)**:
- ❌ `FGTS=0` — firstParty 이미 OFF, 바이너리 확인된 placebo
- ❌ `DISABLE_NONSTREAMING_FALLBACK` — 반대방향
- ❌ 2.1.156 다운그레이드 — 디스크에서 삭제됨 + 156에서도 재현

**유일한 효과적 client 레버**:
- ✅ **Opus 4.7 모델 다운그레이드** — `/model claude-opus-4-7`
- maintainer 문서화 #63604 "즉시 정상화"

**근본 수정**: Anthropic 패치 대기.

**OPEN 이슈**: #63604, #63875, #64129, #64076, #64150, #64235, #64112

**관련 메모**: [[malformed-toolcall-streaming-regression]]

---

## 2. AskUserQuestion 한글 직렬화 버그

**증상**: `InputValidationError: questions type expected array but provided string` → 멈춤

**근거 (검증 2026-05-31 포렌식 18 transcript / 2026-06-01 실측)**

- `AskUserQuestion` 호출 시 한글 텍스트를 `\uXXXX` escape 직렬화하는 과정에서 버퍼 경계 버그로 hex 손상
- `questions` 배열이 string 으로 폴백
- 실측 한 세션 114회 중 25회 실패 = **22%**
- 한글은 영어 대비 escape **23배** (동일 질문 영어 0개 vs 한글 23개) → 한글 사용자가 23배 자주 겪음
- GitHub #30955

**조건**: `AskUserQuestion 도구 호출 + 한글` 조합만 트리거. 일반 한글 응답·설명은 안전 (이 경로 안 탐).

**근본 수정**: Claude Code 본체+서버 버그라 `.claude` 재설치·폰트 변경으로 해결 불가, Anthropic 패치 전까지 클라이언트단 회피만 가능.

**실시간 강제**: `hooks/askuserquestion-bug-guard.sh` (router P0).

**관련 메모**: [[askuserquestion-korean-bug-guard]]

---

## 3. 룰 (CLAUDE.md 본문 참조)

본문 룰은 이 근거 위에 만들어진 **증상 완화 절차**다. 근본 수정 아님.

- [HARD] malformed 1회 발생 시: 다음 호출에서 즉시 올바른 형식으로 재시도
- [HARD] 연속/빈발 시 = `/model claude-opus-4-7` 다운그레이드
- [HARD] 저위험(🟢) 질문은 AskUserQuestion 쓰지 말 것 (본문 마크다운)
- [HARD] 고위험(🔴) 만 AskUserQuestion — 단 payload 전부 영어(ASCII)
