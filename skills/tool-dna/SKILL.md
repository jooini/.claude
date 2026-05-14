---
name: tool-dna
description: 82개 훅의 진화 트리 + deprecated 후보 자동 감지. /tool-dna 로 mtime+코드유사도 기반 가계도, 미등록/형제파일/고유사도쌍 검출. 통합 후보 자동 추천.
---

# Tool DNA — 훅 진화 트리

`~/.claude/hooks/*.sh` 와 `settings.json` 등록 상태를 분석해 훅들의 진화 가계도를 그린다.

## 분석 차원

1. **시간축**: mtime — 가장 오래된 = ancestor 후보
2. **코드 유사도**: shingled jaccard (3-gram 토큰)
3. **명명 클러스터**: prefix (gemma- / gemini- / agent- / commit- 등)
4. **등록 상태**: settings.json 미등록 = 사망 신호
5. **형제 파일**: .bak / .old / .orig / 번호 변종

## Deprecated 신호

- 90일+ 미수정 + settings.json 미등록
- 같은 클러스터에 newer 변종 존재 + 고유사도 짝
- .bak / .old 형제 파일 존재
- 매우 짧은 stub (10줄 미만) + 90일+ 미수정

## 사용법

- `/tool-dna` — 분석 + 리포트 생성
- `/tool-dna show` — 즉시 출력
- `/tool-dna --threshold 0.5` — 더 엄격한 유사도

## 출력

- `~/.claude/cache/tool-dna.md` — 마크다운 리포트
- `~/.claude/cache/tool-dna.dot` — Graphviz DOT 파일
- `~/.claude/cache/tool-dna.json` — 구조화 데이터

## 가시화

```bash
# SVG (브라우저에서 열기)
dot -Tsvg ~/.claude/cache/tool-dna.dot -o ~/.claude/cache/tool-dna.svg
open ~/.claude/cache/tool-dna.svg

# PNG
dot -Tpng ~/.claude/cache/tool-dna.dot -o ~/.claude/cache/tool-dna.png
```

색상:
- 🟢 gemma- 클러스터
- 🔵 gemini- 클러스터
- 🟡 agent- 클러스터
- 회색 = deprecated 후보

## 진짜 가치

- `/hook-audit` 은 충돌/중복을 본다
- `/tool-dna` 는 **혈통과 사망 신호**를 본다
- 79훅이 100개 가기 전에 정리

## 주기적 실행 권장

```bash
# 매주 월 9시
0 9 * * 1 /usr/bin/python3 /Users/leonard/.claude/scripts/tool-dna.py
```
