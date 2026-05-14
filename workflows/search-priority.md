# 코드/문서 검색 우선순위

## 검색 도구 순서

1. `mcp__local-rag__query_documents` (의미론적 + 키워드)
2. `Grep` (정확한 패턴)
3. `Glob` (파일명/경로)
4. `Read` (위 결과에서 확인된 파일)

## 금지 사항

- Explore 에이전트를 코드 검색에 사용하지 말 것
- RAG 없이 바로 Grep/Glob/Read 로 시작하지 말 것
- 서브에이전트 spawn 시 프롬프트에 이 검색 순서를 반드시 포함

## 인덱싱

- 새 파일 생성 후 `ingest_file` 로 RAG 인덱싱 추가

## 작업 유형별 메모리 검색

작업 시작 전 1개 이상 호출 (hook 자동 권고 — `memory-search-suggest.sh`):

| 작업 유형 | 검색 도구 |
|----------|----------|
| 코드 위치/API/구현/디버깅 | `local-rag:query_documents` |
| 과거 결정/판단/반복 실패 패턴 | `claude-mem:mem-search` |
| 디버깅·아키텍처·고위험 변경 | 둘 다 |

**중요**: CLAUDE.md 텍스트만으로는 호출 강제 안 됨 (transcript 검증: 자율 호출 0%). UserPromptSubmit hook 이 발화별로 "[메모리 검색 필수]" system-reminder 주입하면 그때 호출. hook 권고 받으면 **반드시 답변 전 호출**. 권고 없는 짧은 발화는 검색 생략 가능.

상세 배경: `Projects/misc/2026-05/2026-05-10-1256-knowledge-domain-loading-failure-analysis.md`
