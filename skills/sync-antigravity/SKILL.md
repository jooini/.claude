---
name: sync-antigravity
description: Claude Code 설정(스킬, CLAUDE.md, 규칙)을 Antigravity IDE와 동기화합니다. "/sync-antigravity", "/sync ag" 등으로 사용합니다.
argument-hint: "[--dry-run|status]"
---

# sync-antigravity

Claude Code ↔ Antigravity IDE 설정 동기화.

## 사용법

```
/sync-antigravity           → 전체 동기화 실행
/sync-antigravity --dry-run → 변경 예정 사항만 미리보기
/sync-antigravity status    → 현재 동기화 상태 확인
```

## 동기화 대상

| 소스 (Claude Code) | 대상 (Antigravity) | 방식 |
|--------------------|--------------------|------|
| `~/.claude/skills/*` (커스텀) | `~/.gemini/skills/*` | 심링크 |
| `~/.agents/skills/*` (커뮤니티) | `~/.gemini/skills/*` | 심링크 |
| `~/.claude/CLAUDE.md` | `~/.gemini/GEMINI.md` | 변환 생성 |
| `{프로젝트}/CLAUDE.md` | `{프로젝트}/AGENTS.md` | 복사 (최신분만) |

## 실행 절차

### 인자가 `status`인 경우

아래 정보를 조회하여 테이블로 출력한 뒤 종료한다:

1. `~/.gemini/GEMINI.md` 존재 여부 및 수정 시각
2. `~/.gemini/skills/` 내 심링크 수
3. `~/.claude/skills/` 내 전체 스킬 수 (비교)
4. 각 프로젝트별 AGENTS.md 존재 여부 및 CLAUDE.md 대비 최신 여부

```
=== Antigravity 동기화 상태 ===

GEMINI.md: ✓ 존재 (2026-04-05 23:10)
스킬: 891/899 동기화됨 (8개 미동기화)

| 프로젝트 | CLAUDE.md | AGENTS.md | 상태 |
|----------|-----------|-----------|------|
| identity-hub | ✓ | ✓ | 최신 |
| identity-keycloak | ✓ | ✗ | 미동기화 |
| ...
```

### 인자가 `--dry-run`인 경우

아래 모든 단계를 실행하되, 실제 파일 생성/복사/심링크를 수행하지 않고 **예정 작업만 출력**한다.

### 전체 동기화 (기본)

#### 1단계: 글로벌 GEMINI.md 생성

`~/.claude/CLAUDE.md`에서 **Antigravity Gemini 에이전트에 필요한 규칙만** 추출하여 `~/.gemini/GEMINI.md`를 생성한다.

**포함하는 섹션:**
- 커밋 규칙
- 코딩 컨벤션
- 응답 스타일
- 프로젝트 공통 규칙
- SSO 핵심 정책

**제외하는 섹션 (Claude Code 전용):**
- 코드 수정 워크플로우 (파이프라인, 에이전트 호출 등)
- 코드/문서 검색 우선순위 (MCP 관련)
- 서브에이전트 프롬프트 필수 포함 사항
- 도구 역할 분담

GEMINI.md 상단에 아래 역할 선언을 추가한다:
```markdown
# Antigravity 글로벌 규칙

## 역할
Antigravity의 Gemini 에이전트는 병렬 구현 담당. 깊은 추론/리뷰는 Claude Code가 처리.
```

`~/.gemini/GEMINI.md`가 이미 존재하고 `~/.claude/CLAUDE.md`보다 최신이면 건너뛴다.

#### 2단계: 스킬 심링크

`~/.gemini/skills/` 디렉토리를 확인하고, 없는 스킬만 심링크를 생성한다.

**순서:**
1. `~/.agents/skills/*/` → `~/.gemini/skills/` (커뮤니티 스킬)
2. `~/.claude/skills/*/` 중 **심링크가 아닌 실제 디렉토리** → `~/.gemini/skills/` (커스텀 스킬)

이미 존재하는 심링크는 건너뛴다. 끊어진 심링크(dangling)는 제거 후 재생성한다.

**Bash 실행:**
```bash
~/.claude/scripts/sync-antigravity.sh
```

스크립트가 존재하면 실행하고, 없으면 위 절차를 직접 수행한다.

#### 3단계: 프로젝트 AGENTS.md 동기화

아래 프로젝트 목록을 순회하며, CLAUDE.md가 존재하는 프로젝트에 AGENTS.md를 생성/갱신한다:

```
~/Workspace/identity-hub
~/Workspace/identity-keycloak
~/Workspace/maxai-b2c-backend
~/Workspace/identity-hub-frontend
~/Workspace/identity-hub-python-sdk
~/Workspace/keycloak-kakao-social-provider
~/Workspace/sso-fallback-monitor
~/Workspace/maxai-docker
~/Workspace/identity-platform-docker
~/Workspace/ai-agentic-workflow
~/Workspace/maxai
~/Workspace/meeting-minutes
~/Workspace/schedule-app
```

**규칙:**
- CLAUDE.md가 AGENTS.md보다 최신이면 복사
- AGENTS.md가 없으면 새로 생성
- AGENTS.md가 최신이면 건너뛴다
- AGENTS.md는 `.gitignore`에 추가하지 않는다 (Antigravity가 읽어야 하므로)

#### 4단계: 결과 보고

```
=== 동기화 완료 ===
  GEMINI.md:  ~/.gemini/GEMINI.md (생성/갱신/최신)
  스킬:       891개 동기화 (신규 8개, 기존 883개)
  AGENTS.md:  4개 프로젝트 갱신, 9개 최신

Antigravity에서 사용:
  1. Antigravity 열기
  2. 터미널(Cmd+`) → claude 실행
  3. Agent Manager(Cmd+Shift+M)로 병렬 작업
```

## 주의사항

- 이 스킬은 파일 생성/심링크만 수행한다. Antigravity 설정(UI)은 변경하지 않는다.
- GEMINI.md는 CLAUDE.md의 **부분집합**이다. Claude Code 전용 규칙(파이프라인, MCP 검색 순서 등)은 Gemini 에이전트에 불필요하므로 제외한다.
- 커스텀 스킬 중 Claude Code 전용 도구(MCP 등)를 사용하는 것은 Antigravity에서 동작하지 않을 수 있다. 이는 정상이며 무시해도 된다.
- AGENTS.md를 직접 수정하지 말 것. CLAUDE.md를 수정하고 이 스킬을 다시 실행하면 자동 갱신된다.
