---
name: interrupt
description: 인터럽트 큐레이터. /interrupt 로 백그라운드 발견 중 "지금 끼어들 가치"를 점수화 보고. 보안 백로그, 크로스 프로젝트 영향, active/ 누적 등 인터럽트 가치만 필터.
---

# Interrupt Curator — 인터럽트 큐레이터

알림은 집중을 망친다. 이 도구는 **"방해할 권리"를 점수화**한다.

## 분석 차원

- 🔒 **보안 백로그 미처리** — backlog/ 내 "보안/security/HIGH/CRITICAL/RCE" 키워드 (base 50)
- 🌐 **크로스 프로젝트 영향** — 현재 cwd 변경 파일이 다른 프로젝트 active 작업과 겹침 (base 40)
- 🔁 **active 누적** — 5건+ 시 핸드오프/종료 검토 권고 (base 20)
- 🧪 **테스트 미실행 파일** (확장 예정)

## interrupt score

```
score = base_value + category_urgency + (현재 작업과 가까우면 -15)
```

임계값(기본 40) 이상만 보고.

## 사용법

- `/interrupt` — cwd 기준, 임계값 40
- `/interrupt 60` — 임계값 60 (더 엄격)
- `/interrupt --focus "BFF timeout"` — 현재 작업 명시
- `/interrupt json` — JSON 출력

## 절차

```bash
python3 ~/.claude/scripts/interrupt-curator.py --cwd "$PWD" --threshold 40
```

## 출력 예시

```
## 🔒 보안 백로그 미처리: identity-hub / IH-01-rate-limiter (score 75)
- 위치: /Users/leonard/Workspace/identity-hub/backlog/IH-01-rate-limiter.md

## 🌐 크로스 프로젝트 영향 가능: maxai-b2c-backend / sso-migration (score 65)
- 공유 키워드: jwt, validate, session
```

## 자동 실행 (옵션)

주기적 백그라운드 호출 (launchd):

```xml
<!-- ~/Library/LaunchAgents/com.leonard.interrupt-curator.plist -->
<plist>
  <dict>
    <key>Label</key><string>com.leonard.interrupt-curator</string>
    <key>ProgramArguments</key>
    <array>
      <string>/usr/bin/python3</string>
      <string>/Users/leonard/.claude/scripts/interrupt-curator.py</string>
      <string>--threshold</string><string>60</string>
    </array>
    <key>StartInterval</key><integer>1800</integer>  <!-- 30분 -->
  </dict>
</plist>
```

또는 SessionStart 훅에서 1회 호출.

## 한계 (MVP)

- 점수 캘리브레이션은 사용하면서 튜닝 필요
- 거리(현재 작업과 무관함) 측정이 키워드 매칭 수준
- 알림 채널(iTerm badge / Slack) 미통합
