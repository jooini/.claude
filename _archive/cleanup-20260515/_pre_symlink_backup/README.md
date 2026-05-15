# Claude Code Agents

Claude Code용 커스텀 에이전트 + 도메인 지식(Knowledge) 시스템.

## 구조

```
agents/
├── src/            # 에이전트 소스 템플릿 (편집 대상)
├── knowledge/      # 도메인 지식 290개 (빌드 시 에이전트에 삽입)
├── docs/
│   └── common/     # BUILD:COMMON 공통 블록
├── builds/         # 언어별 빌드 결과물
│   ├── root/       # 공통 (언어 특화 없음)
│   ├── python/
│   ├── kotlin/
│   ├── php/
│   └── nodejs/
├── build-agents.sh # 빌드 스크립트
└── *.md → builds/  # 심볼릭 링크 (현재 활성 빌드)
```

## 에이전트 목록

| 에이전트 | 역할 | Knowledge | Model |
|---------|------|-----------|-------|
| backend-developer | BE 개발 (API, DB, 서버) | backend-developer (공통 25 + 언어별) | opus |
| frontend-developer | FE 개발 (React, Vue 등) | frontend-developer (25) | opus |
| ai-engineer | AI/ML 파이프라인 (RAG, 임베딩, 벡터DB) | ai-engineer (24, 런타임 참조) | sonnet |
| code-reviewer | 코드 리뷰 | code-reviewer (20) | sonnet |
| code-tester | 린트/빌드/테스트 실행 | code-tester (20) | sonnet |
| qa | 테스트 전략 수립 | qa (24) | sonnet |
| designer | UI/UX 디자인 | designer (24) | sonnet |
| po | 프로덕트 기획 | po (20) | sonnet |
| data-analyst | 데이터 분석 | data-analyst (24) | sonnet |
| ops-lead | 운영/프로젝트 관리 | ops-lead (24) | sonnet |
| prompt-engineer | 프롬프트 설계 | prompt-engineer (20) | opus |

## 에이전트 프롬프트 구조

각 에이전트(`src/*.md`)는 다음 구조로 구성:

```
Core Identity          — 정체성, 캐릭터
4대 원칙               — 역할별 판단 기준
태스크-지식 매핑        — "이 작업 → 이 knowledge 참조" 라우팅
자율성 매트릭스         — 🟢 자율 / 🟡 알리고 실행 / 🔴 사람 승인
Definition of Done     — 완료 기준 체크리스트
<!-- BUILD:COMMON -->  — 공통 블록 삽입 위치
<!-- BUILD:KNOWLEDGE --> — knowledge 삽입 위치
완료 시 반환 형식       — 산출물 포맷
```

### 자율성 레벨

| 레벨 | 의미 | 예시 |
|------|------|------|
| 🟢 자율 실행 | 되돌릴 수 있는 작업 | 코드 작성, 문서, 리뷰, 분석 |
| 🟡 알리고 실행 | 영향 있는 결정 | 의존성 추가, 구조 변경, 배포 차단 |
| 🔴 사람 승인 | 되돌리기 어려운 결정 | DB 스키마, 프로덕션 배포, 가격/전략, 대외 소통 |

## 설치

```bash
# 1. 복사
cp -r agents/ ~/.claude/agents/

# 2. root 빌드 (기본 — 언어 자동 감지로 모든 프로젝트 대응)
cd ~/.claude/agents
./build-agents.sh
```

## 빌드 옵션

```bash
# 전체 빌드 (CWD 기반 언어 자동 감지)
./build-agents.sh

# 언어 지정 빌드
./build-agents.sh --lang python
./build-agents.sh --lang kotlin

# 빌드 없이 언어 전환 (심볼릭 링크만 교체, 즉시)
./build-agents.sh --use python
./build-agents.sh --use root

# 빌드된 언어 목록 + 현재 활성 확인
./build-agents.sh --list

# 특정 에이전트만 빌드
./build-agents.sh backend-developer

# 압축 없이 전체 knowledge 삽입
./build-agents.sh --full

# 미리보기 (파일 변경 없음)
./build-agents.sh --dry-run
```

## 언어별 Knowledge 로딩

두 가지 방식이 공존:

### 방식 1: 런타임 감지 (기본, 권장)

root 빌드 사용 시, 에이전트가 프로젝트 진입 후 언어를 감지하여 해당 language knowledge를 직접 Read.

```
~/Workspace에서 claude 시작
  → identity-hub 작업 → pyproject.toml 감지 → python knowledge Read
  → b2c-backend 작업 → composer.json 감지 → php knowledge Read
  → identity-keycloak 작업 → build.gradle 감지 → kotlin knowledge Read
```

**장점**: `--use` 전환 없이 같은 세션에서 여러 프로젝트 대응.

### 방식 2: 빌드 타임 내장

언어별 빌드 시, knowledge가 에이전트 프롬프트에 미리 삽입됨.

```bash
./build-agents.sh --lang python    # python knowledge 내장
./build-agents.sh --use python     # 활성화
```

**장점**: 에이전트가 Read 없이 즉시 참조 가능. 토큰 절약.

## BUILD:COMMON 시스템

`docs/common/` 의 공통 규칙을 여러 에이전트에 DRY로 삽입:

```markdown
<!-- BUILD:COMMON docs/common/search-rules.md -->
<!-- BUILD:COMMON docs/common/knowledge-rules.md -->
```

| 공통 블록 | 내용 |
|----------|------|
| `search-rules.md` | 검색 우선순위 (RAG → Grep → Glob → Read) |
| `knowledge-rules.md` | 언어별 knowledge 런타임 로딩 규칙 |

수정 시 해당 파일만 고치고 재빌드하면 전체 에이전트에 반영.

## 동작 원리

1. `src/*.md`에 `<!-- BUILD:COMMON -->`, `<!-- BUILD:KNOWLEDGE -->` 태그가 있음
2. `build-agents.sh`가 해당 위치에 공통 블록/knowledge 파일들을 압축 삽입
3. 결과물이 `builds/{lang}/*.md`로 생성
4. 루트 `*.md`를 활성 빌드로 심볼릭 링크 → Claude Code가 서브에이전트 spawn 시 로딩

## 커스터마이징

- **에이전트 프롬프트 수정**: `src/*.md` 편집 후 `./build-agents.sh` 재빌드
- **Knowledge 추가/수정**: `knowledge/{role}/` 내 `.md` 파일 편집 후 재빌드
- **언어별 Knowledge 추가**: `knowledge/{role}/{lang}/` 디렉토리에 `.md` 파일 추가
- **공통 규칙 수정**: `docs/common/*.md` 편집 후 재빌드
- **품질 기준 참고**: `knowledge/MAINTENANCE.md` — 네이밍, 문체, 파일 크기 등
