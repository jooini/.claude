---
name: logs
description: "서버 로그를 한방에 수집하여 분석하는 스킬. /logs 로 실행하면 로컬 Docker/원격 서버 로그를 수집하고 에러 패턴을 분석한다."
argument-hint: "[프로젝트명 또는 서비스명] [라인수]"
---

# logs

서버 로그를 빠르게 수집하고 에러 패턴을 분석하는 스킬.

## 실행 절차

### 1단계: 대상 결정

`$ARGUMENTS`에서 추출:
- 프로젝트/서비스명 (없으면 현재 디렉토리 기준)
- 라인수 (기본 100)

프로젝트별 로그 소스 매핑:

| 프로젝트 | 로컬 | 원격 (dev) |
|---------|------|-----------|
| identity-hub | `docker logs identity-hub` | `mcp__ssh__runRemoteCommand` dev-sso |
| maxai-b2c-backend | `docker logs b2c-backend` | `mcp__ssh__runRemoteCommand` dev-b2c |
| identity-keycloak | `docker logs keycloak` | `mcp__ssh__runRemoteCommand` dev-sso |
| sso-fallback-monitor | `docker logs fallback-monitor` | — |

### 2단계: 로그 수집 (병렬)

가능한 소스를 **병렬로** 수집:

#### 2-1. Docker 로그 (로컬)

```bash
# 컨테이너 목록 확인
docker ps --format "{{.Names}}" 2>/dev/null | grep -i "{프로젝트명}"

# 로그 수집
docker logs {컨테이너} --tail {라인수} --timestamps 2>&1
```

#### 2-2. 원격 서버 로그

MCP SSH 우선:
```
mcp__ssh__runRemoteCommand(host, "tail -n {라인수} /var/log/{서비스}/error.log")
```

MCP 실패 시 expect:
```bash
expect -c '
  spawn ssh {host}
  expect "password:"
  send "{password}\r"
  expect "$ "
  send "tail -n {라인수} /var/log/{서비스}/error.log\r"
  expect "$ "
  send "exit\r"
  expect eof
'
```

#### 2-3. 애플리케이션 로그 파일

```bash
# 프로젝트 내 로그 파일 탐색
find {프로젝트경로} -name "*.log" -mmin -60 2>/dev/null | head -5
```

### 3단계: 분석

수집된 로그에서:

1. **에러/경고 추출**: ERROR, WARN, Exception, Traceback, Fatal 패턴
2. **빈도 분석**: 같은 에러 반복 횟수
3. **시간순 정렬**: 최근 에러부터
4. **연관 분석**: 에러 직전 요청/이벤트

### 4단계: 결과 출력

```
📋 로그 분석 — {프로젝트명}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
소스: {Docker / SSH / 파일}
기간: {최근 로그 시간 범위}
총 라인: {수집된 라인 수}

🔴 에러 ({N}건)
  1. [{시간}] {에러 메시지} (x{반복횟수})
  2. [{시간}] {에러 메시지}

🟡 경고 ({N}건)
  1. [{시간}] {경고 메시지}

💡 분석
  - {패턴 분석 결과}
  - {추천 조치}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

에러가 발견되면 `/debug`로 이어서 분석할지 제안.

## 주의사항

- 비밀번호, 토큰, 개인정보는 마스킹
- 로그가 너무 길면 에러/경고만 필터링
- 접속 실패 시 다른 소스로 폴백
