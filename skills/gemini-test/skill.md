---
name: gemini-test
description: Gemini CLI로 테스트 코드를 선행 생성합니다. developer 구현과 병렬 실행용.
disable-model-invocation: true
allowed-tools: Bash(gemini *), Bash(ls *), Bash(cat *), Read, Glob, Grep, Write
---

# gemini-test

Gemini CLI의 1M 토큰 컨텍스트를 활용하여 테스트 코드를 선행 생성한다.
developer가 구현하는 동안 병렬로 실행하여, 구현 완료 후 바로 테스트 검증 가능.

## 실행 절차

### 1단계: 프로젝트 스택 감지

현재 디렉토리에서 스택과 테스트 프레임워크를 감지한다.

| 파일 | 스택 | 테스트 프레임워크 |
|------|------|------------------|
| pyproject.toml / requirements.txt | Python | pytest |
| package.json | Node.js | jest / vitest |
| composer.json | PHP | phpunit |
| build.gradle* | Kotlin/Java | JUnit5 |

### 2단계: 기존 테스트 패턴 수집

```bash
# Python
find . -name "test_*.py" -o -name "*_test.py" | head -5 | xargs head -30

# Node.js
find . -name "*.test.ts" -o -name "*.spec.ts" | head -5 | xargs head -30

# PHP
find . -name "*Test.php" | head -5 | xargs head -30
```

### 3단계: Gemini로 테스트 생성

$ARGUMENTS에서 테스트 대상을 파악하고, 기존 테스트 패턴 + 대상 코드를 Gemini에 넘겨 테스트 생성.

```bash
gemini -p "다음 기능에 대한 테스트 코드를 작성해줘:
[기능 설명]

기존 테스트 패턴:
[기존 테스트 코드 샘플]

대상 인터페이스:
[대상 코드/인터페이스]

테스트 프레임워크: [감지된 프레임워크]
기존 테스트 패턴을 따를 것.
한글 주석, 코드는 영어."
```

### 4단계: 결과 저장

Gemini 결과를 적절한 테스트 파일에 Write.
- Python: `tests/test_{module}.py`
- Node.js: `src/{module}.test.ts` 또는 `__tests__/{module}.test.ts`
- PHP: `tests/{Module}Test.php`

기존 테스트 파일이 있으면 기존 파일에 추가. 없으면 새로 생성.

### 5단계: 결과 보고

생성된 테스트 파일 경로와 테스트 케이스 수를 보고.

## 입력

$ARGUMENTS

위 절차에 따라 테스트 코드를 생성하세요.
