---
name: deep-research
description: Gemini CLI로 기술 심층 조사를 수행합니다. 라이브러리 비교, 마이그레이션 전략, 보안 분석 등.
disable-model-invocation: true
allowed-tools: Bash(gemini *), Bash(ls *), Read, Glob, Grep, Write
---

# deep-research

Gemini CLI의 대용량 컨텍스트를 활용하여 기술 심층 조사를 수행한다.

## 조사 유형

| 유형 | 트리거 키워드 | 접근 방식 |
|------|-------------|----------|
| 라이브러리 비교 | "비교", "vs", "대안" | 후보 라이브러리 문서/코드 분석 |
| 마이그레이션 전략 | "마이그레이션", "업그레이드", "전환" | 현재 코드베이스 + 대상 버전 변경사항 분석 |
| 보안 분석 | "보안", "취약점", "CVE" | 의존성 + 코드 패턴 보안 스캔 |
| 아키텍처 설계 | "설계", "아키텍처", "구조" | 현재 구조 분석 + 개선안 도출 |
| 성능 분석 | "성능", "최적화", "병목" | 코드 프로파일링 포인트 + 개선안 |

## 실행 절차

### 1단계: 조사 주제 파악

$ARGUMENTS에서 조사 주제와 유형을 파악.

### 2단계: 코드베이스 컨텍스트 수집

현재 프로젝트의 관련 코드를 Gemini에 넘길 컨텍스트로 수집.

```bash
# 프로젝트 전체 구조
find . -type f \( -name '*.py' -o -name '*.ts' -o -name '*.kt' -o -name '*.php' \) \
  -not -path '*/node_modules/*' -not -path '*/__pycache__/*' -not -path '*/.git/*' | head -200
```

### 3단계: Gemini 실행

```bash
"${GEMINI_CLI:-agy}" -p "[조사 주제]

프로젝트 컨텍스트:
[코드베이스 구조/관련 파일]

다음을 포함하여 분석해줘:
1. 현재 상태 분석
2. 선택지 비교 (장단점)
3. 권장안 + 근거
4. 실행 계획 (단계별)
5. 리스크와 대응 방안

한글로 답변, 기술 용어는 영어 유지." < <(관련 파일 내용)
```

### 4단계: 결과 저장

조사 결과를 Obsidian vault에 저장:
- 경로: `~/Workspace/weaversbrain/weaversbrain/Projects/{project}/YYYY-MM/YYYY-MM-DD-HHMM-{주제}-research.md`
- frontmatter: `type: research`

### 5단계: 결과 보고

obsidian:// URI와 함께 핵심 요약 출력.

## 입력

$ARGUMENTS

위 절차에 따라 기술 심층 조사를 수행하세요.
