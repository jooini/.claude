---
name: dev-data-collector
description: "지난 분기/연도 또는 임의 기간의 개발 활동(git/PR/Obsidian) 객관 수치를 스캔하여 Reports/snapshots/에 portrait.md 스냅샷을 생성한다. 주관 판단 금지. 해석은 career-analyzer에서 수행. '/collect', '/collect quarter', '/collect year', '/collect range 2026-04-01 2026-06-30' 등으로 트리거."
argument-hint: "[quarter|year|range FROM TO|custom --from FROM --to TO --scope PATTERN]"
disable-model-invocation: true
allowed-tools: Bash(python3 *), Bash(git *), Bash(gh *), Bash(date *), Bash(ls *), Bash(basename *), Read, Write, Glob
---

# dev-data-collector

개발 활동 raw 스냅샷 생성기. 주관 개입 0, 재현 가능.

## 사용법

```
/collect                                   # 지난 분기 (기본)
/collect quarter                           # 지난 분기
/collect year                              # 지난 1년
/collect range 2026-04-01 2026-06-30       # 기간 직접
/collect custom --from 2026-01-01 --to 2026-03-31 --scope "sso-*,identity-hub*"
```

## 실행 규칙

1. **핵심 실행은 Python 스크립트**: `~/.claude/scripts/dev-data-collector.py`
   - 이 스크립트가 모든 수집/집계/렌더링을 담당한다
   - 스킬 본체는 **얇은 래퍼** 역할만 한다
2. **주관 개입 금지** — 아래는 원칙적으로 수집 결과에 추가/수정해서는 안 된다
   - "많다/적다", "잘했다/못했다", "~경향이 있다" 같은 서술
   - 스크립트가 출력하지 않은 수치 생성
3. 스크립트 실패 시에도 fallback 문서 생성 금지. 에러를 있는 그대로 보여주고 사용자에게 보고.

## 실행 절차

### 1단계: 인자 파싱

- `$ARGUMENTS`가 비어 있으면 `quarter` 처리
- 허용 서브커맨드: `quarter`, `year`, `range`, `custom`
- 기타는 바로 스크립트에 그대로 전달

### 2단계: 스크립트 실행

```bash
python3 ~/.claude/scripts/dev-data-collector.py $ARGUMENTS
```

- 출력: `~/Workspace/weaversbrain/weaversbrain/Reports/snapshots/{label}-portrait.md`
  + JSON sidecar `{label}-portrait.json`
- 진행 로그는 stderr로 출력됨
- 실행 시간이 길 수 있음 (100+ 레포 스캔) — timeout 없이 wait

### 3단계: 결과 확인

- 생성된 `portrait.md` 경로 출력
- 간단 요약(2~3줄) 출력: 총 커밋, 활성 레포 수, 범위
- obsidian:// URI 출력 (예: `obsidian://open?vault=weaversbrain&file=Reports/snapshots/2026-Q2-portrait`)

### 4단계: 후속 안내

> 다음 단계: `/analyze performance-cycle {label}` 를 실행하면 이 스냅샷을 기반으로 해석 문서를 만듭니다.

## 출력 스키마 개요 (스크립트가 생성)

`portrait.md` 섹션 순서 고정:

1. 레포별 커밋 볼륨 (표)
2. 작업 유형 분포 (`feat`/`fix`/`refactor`/... 카운트)
   - 2.1 커밋 메시지 언어 분포 (ko/en/mixed)
3. PR & 리뷰 활동 (`gh` 있을 때만)
4. 파일 오버랩 (협업 시그널)
5. 파일 TOP-20 (변경 횟수)
6. 리듬 (요일·시간대·월별)
7. 메타 자산 (문서/테스트/CI/의존성 변경 카운트)
8. Obsidian 활동 (Daily 노트, 단어 수)
9. 프로젝트 그룹별 요약 (identity-hub / maxai / sso / ...)
10. 원본 데이터 출처 (재현 가능성 — 사용된 git 명령)

스키마를 수정하려면 스크립트의 `render_markdown()` 수정 + 이 문서의 §출력 스키마 동기화.

## 주의사항

- git config `user.email` 기준으로 저자 필터. 다른 계정으로 쓴 커밋은 `--email` 옵션으로 오버라이드.
- 스코프 패턴은 `~/Workspace/` 바로 아래 디렉토리 이름에 대한 fnmatch.
- `gh` CLI 없거나 인증 안 되면 PR 섹션 스킵 (에러 아님).
- **재실행은 안전**: 같은 기간 재실행하면 파일 덮어씀. 수동 편집한 스냅샷은 덮어쓰기 전 확인 필요.
- 민감 정보: 커밋 메시지 그대로 담음. 외부 공유 시 `career-analyzer --audience=external` 사용.
- Obsidian Vault 위치가 바뀌면 스크립트의 `VAULT` 상수 수정.

## 입력

$ARGUMENTS

위 인자를 그대로 Python 스크립트에 전달하여 실행하세요. 스크립트 출력 외의 수치/판단을 추가하지 마세요.
