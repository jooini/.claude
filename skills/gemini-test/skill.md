---
name: gemini-test
description: 중앙 LLM 라우터를 통해 Gemini provider에 테스트 코드 초안을 요청한다. developer 구현과 병렬 실행용.
disable-model-invocation: true
allowed-tools: Bash(~/.agents/scripts/llm-router.sh *), Bash(/Users/leonard/.agents/scripts/llm-router.sh *), Read, Glob, Grep, Write
---

# gemini-test

Gemini provider의 대규모 컨텍스트를 활용해 테스트 초안을 만든다. 직접 provider CLI를 실행하지 않고 `~/.agents/scripts/llm-router.sh scan --provider gemini`를 사용한다.

## 실행 절차

### 1단계: 프로젝트 스택 감지

현재 디렉토리에서 스택과 테스트 프레임워크를 감지한다.

| 파일 | 스택 | 테스트 프레임워크 |
|------|------|------------------|
| `pyproject.toml` / `requirements.txt` | Python | pytest |
| `package.json` | Node.js | jest / vitest |
| `composer.json` | PHP | phpunit |
| `build.gradle*` | Kotlin/Java | JUnit5 |

### 2단계: 기존 테스트 패턴 수집

기존 테스트 파일 몇 개를 읽어 naming, fixture, assertion 스타일을 파악한다.

### 3단계: Gemini provider로 테스트 초안 요청

```bash
~/.agents/scripts/llm-router.sh scan --caller gemini-test --provider gemini --prompt "다음 기능에 대한 테스트 코드 초안을 작성해줘:
[기능 설명]

기존 테스트 패턴:
[기존 테스트 코드 샘플]

대상 인터페이스:
[대상 코드/인터페이스]

테스트 프레임워크: [감지된 프레임워크]
기존 테스트 패턴을 따를 것.
한글 설명, 코드는 영어."
```

### 4단계: 테스트 파일 반영

Gemini 출력은 초안이다. 현재 세션의 작업자가 내용을 검토한 뒤 적절한 테스트 파일에 반영한다.

- Python: `tests/test_{module}.py`
- Node.js: `src/{module}.test.ts` 또는 `__tests__/{module}.test.ts`
- PHP: `tests/{Module}Test.php`

## 입력

$ARGUMENTS

위 절차에 따라 테스트 코드를 생성한다.
