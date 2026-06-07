# Codex 필수 활용 매핑

> CLAUDE.md에서 `@~/.claude/workflows/codex.md` 로 참조됨.

**경로 정책 (2026-05-30 전환)**: `mcp__codex-cli__*` MCP는 이 환경에서 세션 로드 안 됨("No such tool", ENABLE_TOOL_SEARCH=false 환경). 공식 OpenAI 플러그인도 MCP 미제공. **Codex는 `codex:` 플러그인 명령 + `codex exec` CLI + `ask-codex` 스킬로만 호출**한다. MCP 도구 호출 시도 금지.

## 상황별 도구 매핑

| 상황 | Codex 진입점 | 실행 방식 |
|------|-------------|----------|
| 코드 구현/수정 (대안) | `codex:parallel-impl` 또는 `codex exec --write` | developer 에이전트와 **병렬** 구현, 최선안 채택 |
| 코드 수정 후 리뷰 | `codex:review` | code-reviewer 에이전트와 **병렬** |
| 구현 세컨드 오피니언 | `Skill(ask-codex)` (read-only) | developer 에이전트와 **병렬** |
| 디버깅 3회 실패 | `codex:rescue` | **foreground** 에스컬레이션 (background 금지 — 결과 수집 불가) |
| 보안/DB/인프라/API breaking | `codex:adversarial-review` | 격상 검증 |
| PR 생성 전 최종 검증 | `codex:review` | 단독 실행 |
| 설계 판단 (3파일+) | `Skill(ask-codex)` (read-only, effort high) | 세컨드 오피니언 |
| 빠른 질문/패치 검토 | `Skill(ask-codex)` | CLI 1회, 결론만 요약 |

## Codex 주도 + Claude Code 병행 워크플로우

Codex에서 작업을 시작한 세션의 기본 소유자는 Codex다. Claude Code는 같은 워크트리를 직접 수정하는 두 번째 작업자가 아니라, read-only 판단 보조자/리뷰어/오케스트레이터로만 병행한다. 코드 적용, 테스트 실행, 최종 사용자 응답은 현재 Codex 세션이 책임진다.

### 병행 트리거

| 상황 | Claude Code 역할 | 산출물 |
|------|------------------|--------|
| `claude 같이`, `claude도`, `둘 다`, `하이브리드`, `hybrid` 명시 | 요청 분해와 역할 라우팅 | `~/.claude/cache/claude/{project}-codex-brief.md` |
| 3파일 이상 영향, 아키텍처/설계/API/DB/auth 변경 | 위험 포인트와 먼저 볼 파일 선정 | brief 또는 현재 답변에 반영 |
| Codex 구현안과 기존 규칙/테스트가 충돌 | 판단 기준 제시 | 채택/기각 근거 |
| 리뷰 지적이 2회 이상 반복되거나 디버깅이 꼬임 | 접근 재정렬 | rescue 전 점검 메모 |
| PR/커밋 직전의 큰 변경 | 최종 리뷰 관점 보강 | 누락 테스트/회귀 위험 목록 |

### 실행 순서

1. Codex는 프로젝트 규칙(`AGENTS.md`, `CLAUDE.md`, `.claude/agents/*`, `~/.claude/workflows/*`)을 먼저 읽는다.
2. 최근 Claude brief가 있으면 먼저 참고한다. fresh 기준은 15분이다.
3. brief가 없고 병행 트리거가 있으면 Claude Code에 read-only brief를 요청한다. 자동 훅이 활성화된 환경에서는 `UserPromptSubmit` 훅이 만들 수 있고, 아니면 수동으로 만든다.
4. Codex는 Claude brief를 근거 자료로만 취급한다. 실제 파일/테스트/프로젝트 규칙과 다르면 프로젝트 실제 상태를 우선한다.
5. 코드 수정은 Codex가 단독으로 적용한다. Claude Code가 동시에 같은 워크트리에 쓰기 작업을 하게 하지 않는다.
6. 구현 뒤에는 Codex가 테스트/리뷰를 실행하고, 필요하면 `codex:review` 또는 `llm-router.sh review`로 추가 검증한다.

### 수동 Claude Brief

자동 훅이 꺼져 있거나 Codex 세션에서 명시적으로 Claude Code 관점이 필요하면 아래 계약으로 brief를 만든다. 출력은 짧은 메모만 저장하고, 패치 작성은 금지한다.

```bash
cd /path/to/project
project="$(basename "$PWD")"
mkdir -p "$HOME/.claude/cache/claude"
claude -p --tools '' --model sonnet "Codex가 작업 중이다. 코드는 수정하지 말고, 요청을 수행하기 위한 실행 메모만 한글 12줄 이내로 작성해라: 추천 역할/에이전트, 병렬 가능 작업, 먼저 읽을 파일, 위험 포인트." > "$HOME/.claude/cache/claude/${project}-codex-brief.md"
```

저장 위치:

```text
~/.claude/cache/claude/{project}-codex-brief.md
```

### 충돌 규칙

- Codex와 Claude Code의 판단이 다르면 추정으로 고르지 말고 파일 읽기, 테스트, git diff로 검증한다.
- Claude Code brief는 read-only 의견이다. 사용자 지시나 프로젝트 규칙보다 우선하지 않는다.
- 같은 워크트리에 두 도구가 동시에 write하면 안 된다. 병렬 구현이 필요하면 worktree를 분리한다.
- 보안/DB/인프라/API breaking change는 Claude brief만으로 끝내지 않고 `codex:adversarial-review`까지 격상한다.

## CLI 직접 호출 규약

```bash
# 분석/세컨드오피니언 (read-only 의도)
codex exec --skip-git-repo-check "질문"

# 대량 구현 위임 (write)
codex exec --skip-git-repo-check --write "구현 태스크"

# PATH 누락 시 절대경로 (which codex 는 'not found' stdout 오염 → 절대경로 직접)
/Users/leonard/.nvm/versions/node/v22.22.0/bin/codex exec --skip-git-repo-check "질문"
```

함정 (검증됨 2026-05-30):
- `codex -a "..."` → `--ask-for-approval` 로 오해석. 반드시 `codex exec` 형태
- 비-git 디렉토리(`~/.claude` 등) → `--skip-git-repo-check` 필수
- 출력 정리: `2>&1 | grep -v "^hook:" | tail -N` 로 노이즈 제거
- 프롬프트 위험 키워드(DROP/rm) → danger-keyword 훅 오탐 가능, 우회 표현
- 모델: config.toml 기본 gpt-5.5/xhigh/full-auto. 단순 작업은 `-c model=gpt-5.4` 비용 절감

## 우선순위

- `codex:` 플러그인 명령이 1순위 (공식 OpenAI, companion 런타임으로 안정)
- `Skill(ask-codex)` 는 파이프라인 밖 임시 질문/분석용 — 내부 호출은 `codex exec` CLI
- `permissions.allow` 에 `Bash(codex exec *)`, `Skill(ask-codex)` 등록됨 → 권한 프롬프트 없음

## 규칙 요약

- 코드 수정 후 리뷰 → code-reviewer 에이전트 + `codex:review` **병렬 실행** (규모 무관)
- 보안/DB/인프라/API breaking change → `codex:adversarial-review` 로 격상
- developer→tester 3회 실패 → `codex:rescue` **foreground** 에스컬레이션
- M/L 규모 → developer 구현과 `codex:parallel-impl` 대안 구현 병렬 실행, Claude Code가 최선안 채택
- Codex 주도 세션에서 Claude Code는 read-only brief/리뷰 역할로 병행하고, 동일 워크트리 동시 write는 금지
- 같은 질문을 Gemini에 중복 요청 금지
