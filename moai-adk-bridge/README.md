# MoAI-ADK ↔ Codex/Agy Bridge

이 폴더는 MoAI-ADK task를 Codex 또는 Agy 실행기로 흘려보내기 위한 최소 브릿지 스텁입니다.

브릿지 경로는 `/Users/leonard/.claude/moai-adk-bridge`이며, 실행은 `/Users/leonard/.claude/bin/moai-adk`로 바로 호출할 수 있습니다.

목표는 `runner`를 추가해도 **입력 포맷/상태/출력 포맷을 고정**하고,
실행기 교체만 가능한 형태로 점진 확장하는 것입니다.

## 구조

- `contracts/task-envelope.json`
  - 공통 TaskEnvelope 스키마
- `bin/translate.js`
  - moai-adk input을 브릿지 TaskEnvelope로 정규화
- `bin/run.js`
  - TaskEnvelope 실행기 디스패치(Codex/Agy) + 결과 정규화
- `samples/`
  - `auto/agy/codex` 샘플 입력 3종으로 E2E 확인 지원

## 실행 흐름

1. moai-adk 입력 받기
2. `translate.js`로 공통 `TaskEnvelope` 정규화
3. `run.js`로 runner 매핑 및 실행
4. 실패 시 retry 정책 적용
5. `status`, `artifacts`, `next_step`, `state` 형태로 moai 포맷 출력

## 기본 runner 정책

- `scan`, `analyze`, `investigate`: 기본 `agy` (빠른 텍스트 탐색 위주)
- `edit`, `refactor`, `implement`: 기본 `codex` (변경/리팩토링 중심)
- `review`, `handoff`, `validate`, `test`, `rollback`: 기본 `codex`
- `runner: "auto"`이면 위 매핑 사용

## 사용 예시

```bash
# moai-adk 입력 파일을 브릿지 포맷으로 변환
node /Users/leonard/.claude/moai-adk-bridge/bin/translate.js --input task.json

# 브릿지 실행 (자동으로 codex/agy 분기)
node /Users/leonard/.claude/moai-adk-bridge/bin/run.js --task task.json
```

샘플 기반 파이프라인:

```bash
cat samples/sample-auto-scan.json | node /Users/leonard/.claude/moai-adk-bridge/bin/translate.js | node /Users/leonard/.claude/moai-adk-bridge/bin/run.js
cat samples/sample-agy-investigate.json | node /Users/leonard/.claude/moai-adk-bridge/bin/translate.js | node /Users/leonard/.claude/moai-adk-bridge/bin/run.js
cat samples/sample-codex-implement.json | node /Users/leonard/.claude/moai-adk-bridge/bin/translate.js | node /Users/leonard/.claude/moai-adk-bridge/bin/run.js
```

래퍼 실행:

```bash
moai-adk --task samples/sample-auto-scan.json
cat samples/sample-auto-scan.json | moai-adk
```

## 실행 결과 포맷(요구사항)

- 항상 `status`, `artifacts`, `next_step`이 존재
- 실패 시 `error_summary`, `retry_plan`을 포함
- 재개용 체크포인트는 `state`에 보관

`state` 필수 항목:
- `task_id`, `phase`, `last_step`, `timestamp`, `artifacts`, `next_action`

## 다음 단계(권장)

1. `runner`별 실제 실행기를 실제 운영환경 명령으로 치환
2. 스테이지별 보정 규칙 추가(예: 파일 확장자, 변경 제한, 승인 정책)
3. 샘플 3개 태스크로 `auto`, `agy`, `codex` E2E 확인
