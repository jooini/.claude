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
- 같은 질문을 Gemini에 중복 요청 금지
