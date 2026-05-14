---
name: qq
description: Question Quality Meter — 252+ 세션 사용자 발화 분석으로 어떤 발화가 정정을 유발하는지 학습. /qq 로 사용자 자기 발화 통계 + 모호 패턴 자동 추출.
---

# Question Quality Meter

사용자(leonard)의 과거 발화 패턴을 학습해 다음 발화의 모호도를 예측.

## Outcome 라벨링

각 user 발화 직후 5턴 내:
- **BAD**: 사용자 정정 발생 ("아니/틀렸/수정해")
- **GOOD**: 명확한 ack ("응/ok/고마워")
- **NEUTRAL**: 그 외 정상 진행
- **UNKNOWN**: 다음 user 발화 없음

## 모호도 패턴

- 매우 짧은 발화 (< 5자)
- 모호 키워드 ("좀/그냥/알아서/적당히/대충")
- 지시대명사 ("그것/거기/아까/저번에")
- 구체성 0 (파일경로/숫자/대문자명사 없음)

## 사용법

- `/qq` — 분석 + 리포트
- `/qq show` — 즉시 출력
- `/qq --max-sessions 50` — 더 작게

## 출력

- `~/.claude/cache/question-quality.md`
- `~/.claude/cache/question-quality.json`
- `~/.claude/cache/question-quality-rules.json` (다른 도구 입력으로 사용)

## 진짜 가치

사용자 메모리/피드백은 흔하지만 **"내 발화 자체"** 를 측정한 적은 없다. 수치로 보면 행동이 바뀐다.

예:
> "당신 발화의 47%가 5자 미만이고, 그중 31%가 5턴 내 정정 유발"

→ 다음에 짧게 쓰지 말고 한 줄 더 쓰자.

## 후속 활용 (미구현)

UserPromptSubmit 훅에서 현재 발화 features 추출 → rules 와 매칭하여 임계값 초과 시 stderr 경고:

```
⚠️ 이 발화 패턴: 짧음+모호+지시대명사 → 정정 유발 73%
   더 명확하게 쓰면 다음 5턴이 안전합니다.
```
