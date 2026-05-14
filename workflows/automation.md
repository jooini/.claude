# 워크플로우 자동화 (메트릭·규모·결정)

## Gemini/Codex 자동 트리거

hooks가 자동 처리:
- 의존성 변경 → Gemini 분석
- 테스트 3회 실패 → Codex rescue
- PR 생성 → Codex 요약
- 프로젝트 전환 → Gemini 스캔

추가 자동 트리거:
- 코드 구조 질문 → Gemini 스캔
- 업그레이드 → Gemini 영향 스캔
- 버그 → Codex 재현
- 설계 판단(3파일+) → Codex 세컨드 오피니언

## 훅 자동 동작

- **규모 자동 판별** (`auto-scale-detect.sh`): UserPromptSubmit에서 파이프라인 키워드 감지 시 git diff 파일 수로 S(1~2)/M(3~5)/L(6+) 자동 라벨. 아키텍처 키워드 포함 시 무조건 L. 사용자가 "L 규모로" 명시하면 우선
- **파이프라인 메트릭** (`pipeline-metrics-log.sh`): PostToolUse(Agent)에서 에이전트별 실행 시간·성공여부 자동 기록 → `~/.claude/cache/metrics/YYYY-MM-DD.tsv`
- **결정 자동 캡처** (`decision-capture.sh`): code-reviewer/Plan/qa/po/developer 등 출력에서 "결정:", "채택:", "기각:", "Decision:", "Selected:", "Rejected:" 패턴 추출 → Obsidian Vault `decisions/` 자동 저장
- **PostToolUse(Bash) 통합 hook** (`bash-postproc-sync.sh` + `bash-postproc-async.sh`, 2026-05-14 통합): branch 전환 감지 / cwd 변경 시 언어·agent build 전환 / Workspace 진입 시 Gemini 스캔 / 테스트 3회 실패 시 Gemini 영향 분석 / tool-trace JSONL 적재 / gemini·codex CLI usage 로깅. 6개 옛 hook을 2개로 통합하여 stdin 1회 파싱으로 hook latency 약 460ms/호출 절감

## 회고 스킬

- `/retro [N일]` — 파이프라인 효과 측정 리포트 (호출 빈도·평균 시간·실패율)
- `/decisions [검색어]` — 자동 캡처된 과거 결정 검색
