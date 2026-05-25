# Project Interview

Date: 2026-05-25
Conversation language: ko (Korean)
Target directory: /Users/leonard/.claude (the user's personal Claude Code harness)
Project type detected: Existing Project (847 source files: bash/python/ts/js)

## Round 1: Ownership and Purpose

Question:
이 `~/.claude` 하네스는 현재 어떤 단계의 프로젝트인가요?

Answer:
**적극 진화 중인 개인 R&D 시스템.**
- 매일의 작업으로 진화하는 자가 적응형 하네스.
- 문서는 현재 상태와 '진화의 방향'(autoresearch, self-research, R2-D2 absorbed MoAI, evaluator-active)을 함께 반영해야 함.
- 일대일 이양의 잘 자는 R&D 시스템으로 서술.

## Round 2: Constraints and Non-Goals

Question:
문서에서 명시해야 할 '립스고 하지 않는 것'이 있나요?

Answer:
**타인과 공유용이 아니다.**
- 이건 온전히 개인·관찰 도구이며 일반 배포를 위한 시스템이 아님.
- `CHEATSHEET.md`, `identity-hub/`, `mcp-needs-auth-cache.json` 등은 개인 환경 종속.
- 구조적 공유는 마조일으로도 제공하지 않음을 명시.

## Round 3: Documentation Priority

Question:
무엇을 가장 정확하게 잡아야 하나요?

Answer:
**아키텍처 · 모듈 경계 · 데이터 흐름.**
- `agents/skills/hooks/commands/workflows`가 서로 어떻게 신호를 주고받는지.
- 이벤트 흐름이 어떻게 이어지는지.
- 명령형 하네스의 서술 최적.

---

## Derived Documentation Constraints

이 인터뷰 결과는 Phase 3 문서 생성 시 다음과 같이 반영되어야 함:

1. **product.md**
   - "개인 R&D 자가 적응형 하네스" 정체성을 첫 문장에 명시.
   - 타겟 오디언스: **사용자 본인(joo.leonard@gmail.com)** + 미래의 자기 자신. 공유 대상 없음.
   - 진화 방향(autoresearch / R2-D2-absorbed MoAI / evaluator-active / self-research) 섹션 별도 명시.
   - "Out of Scope" 섹션에 공유/배포 비목표 명시.

2. **structure.md**
   - 모듈 경계(agents, skills, hooks, commands, workflows, rules, scripts, plugins, .moai, cache 계열) 우선 서술.
   - 각 디렉토리의 역할 + 다른 디렉토리와의 신호 인터페이스 명시.
   - 데이터 흐름 (UserPrompt → hook → skill auto-load → agent delegation → tool call → hook PostToolUse → memory/intent persist) 별도 다이어그램/시퀀스.

3. **tech.md**
   - 주력: bash + python + markdown + yaml + json.
   - MCP 서버 5종 (.mcp.json 기반).
   - 보안 훅(commit-no-coauthor, dangerous-command-detect, gemini-prescan-enforcer 등) 별도.
   - CI 부재 — 의도적 선택임을 명시(인터뷰 Round 2 보강).

4. **codemaps/**
   - overview.md, modules.md, dependencies.md, entry-points.md, data-flow.md.
   - 데이터 흐름 다이어그램이 핵심 산출물.
