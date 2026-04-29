---
name: puzzle
description: "버그 증상을 Gemma에 넘겨 원인 가설 3개 + 읽기 전용 검증 명령 자동 생성. /puzzle \"증상\" 으로 호출. --run 옵션 주면 검증 명령 자동 실행. 디버깅 첫 30분 자동화."
argument-hint: "<버그 증상>"
disable-model-invocation: true
allowed-tools: Bash(python3 *)
---

# /puzzle — 디버깅 가설 자동 생성

버그 증상 던지면 Gemma가 원인 가설 3개 + 검증 명령(읽기 전용)을 생성. 선택적으로 자동 실행.

## 실행

```bash
python3 ~/.claude/scripts/gemma-puzzle.py $ARGUMENTS
```

## 사용 예

### 기본 — 가설만 생성
```
/puzzle 로그인 500 에러, Keycloak 응답 없음
```

### 자동 실행 모드 — 가설별 검증 명령 실행까지
```
/puzzle --run "도커 컨테이너 healthcheck 실패"
```

### stdin 파이프 — 에러 로그 붙여넣기
```bash
cat error.log | python3 ~/.claude/scripts/gemma-puzzle.py
```

## 출력 형식

```
## 가설 1: JWT 토큰 만료
   검증명령: curl -s -H "Authorization: Bearer $TOKEN" https://api.example.com/auth/check
   예상결과: 401 Unauthorized + "token expired"

## 가설 2: 네트워크/DNS 이슈
   검증명령: ping -c 3 sso.example.com && nslookup sso.example.com
   예상결과: 응답 없음 또는 DNS 실패

## 가설 3: 백엔드 서비스 다운
   검증명령: docker ps | grep identity-hub
   예상결과: 컨테이너 미실행 또는 health=unhealthy
```

## 안전장치

**`--run` 옵션 사용 시**:
- **읽기 전용 명령만 실행** (자동 검증)
- 위험 명령 차단: `rm`, `mv`, `sudo`, `kill`, `chmod`, `>`, `git push`, `drop`, `delete from` 등
- 허용 prefix: `curl`, `grep`, `ls`, `cat`, `git log/status/diff/show`, `ps`, `docker ps/logs`, `lsof`, `netstat`, `find`, `wc`, `env` 등
- 타임아웃 15초/명령

## 언제 쓰면 좋은가

- 프로덕션 장애 시작 시 — 감 잡기용
- 테스트 실패 반복될 때 — 가설 브레인스토밍
- 에러 메시지 애매할 때 — 근본 원인 후보 생성
- `/debug` 스킬 들어가기 전 사전 조사

## 한계

- 가설은 **추측** — Gemma 환각 가능
- 도메인 지식 깊이는 Claude가 낫다 — 최종 판단은 Claude
- 자동 실행은 **읽기 전용만** — 수정/배포는 사람 결정

## 다음 단계 워크플로우

1. `/puzzle "증상"` → 가설 3개 확보
2. 가장 유력한 가설 → Claude에 "이거 검증해줘"
3. `/debug` 스킬로 본격 디버깅
4. 수정 후 `/go` 또는 파이프라인 검증

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| "가설 파싱 실패" | Gemma 형식 무시 | 재실행 |
| Ollama 접근 불가 | 서버 다운 | 수동 가설 |
| 응답 비어있음 | num_predict 부족 | 스크립트 조정 |
