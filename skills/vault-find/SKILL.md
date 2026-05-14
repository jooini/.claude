---
name: vault-find
description: Obsidian Vault(weaversbrain) 정리노트를 빠르게 검색. 풀텍스트(ripgrep) + frontmatter 메타 + 의미론(local-rag) 통합. `/vault-find` 단독은 최근 14일 노트, `/vault-find {keyword}` 는 풀텍스트 + 메타, `--project`, `--tag`, `--recent N` 필터, `--semantic` 으로 의미론 힌트. 결과는 obsidian:// 링크 포함 마크다운 표.
---

# vault-find — Obsidian Vault 검색

이전 세션에서 정리한 노트가 어디 있는지 빠르게 찾는다.
인덱스는 `~/.cache/weaversbrain-vault-index.json`. 6시간 이상 오래되면 자동 갱신.

## 사용

| 호출 | 동작 |
|------|------|
| `/vault-find` | 최근 14일 정리노트 |
| `/vault-find {keyword}` | 제목/태그/경로 + 풀텍스트 모두 검색 |
| `/vault-find --project identity-hub` | 프로젝트 필터 |
| `/vault-find --tag pkce` | 태그 필터 |
| `/vault-find --recent 7` | 최근 N일 |
| `/vault-find {kw} --semantic` | 의미론 검색 힌트 (`mcp__local-rag` 호출 안내) |
| `/vault-find {kw} --limit 50` | 결과 개수 |
| `/vault-find {kw} --paths-only` | 다른 도구에 파이프할 때 |

복합:
```
/vault-find PKCE --project identity-hub --recent 30
/vault-find onboard --paths-only | xargs -I{} grep -l "client_secret" {}
```

## 실행 절차

1. `python3 ~/.claude/skills/vault-find/scripts/search.py {인자들}` 실행
2. 인덱스가 6시간 이상 오래됐으면 자동 재생성 (`~/Workspace/weaversbrain/weaversbrain/scripts/build_vault_index.py --quiet` 호출)
3. 결과: 마크다운 표 (날짜 / 프로젝트 / 제목 / 태그 / `obsidian://` URI 링크)
4. `--semantic` 플래그가 있으면 본 응답 직후 **`mcp__local-rag__query_documents(query="{keyword}")`** 도구를 직접 호출해서 의미론 검색 결과를 추가로 보여줄 것

## 출력 예

```
# vault-find · keyword=`PKCE` · project=`identity-hub`

_총 12개 일치. 인덱스 생성: 2026-05-14T23:19:05_

| 날짜 | 프로젝트 | 제목 | 태그 | 열기 |
|------|----------|------|------|------|
| `2026-05-14` | identity-hub | ih-integrate 스킬 설계 ... | #pkce #rfc-8252 | [열기](obsidian://...) |
```

`[열기]` 링크를 클릭하면 Obsidian 에서 해당 노트가 열린다.
사내 동료에게 공유 시 obsidian:// URI 그대로 복사하면 동일 Vault 가진 사람은 한 클릭.

## 인덱스 갱신 수동

```bash
python3 ~/Workspace/weaversbrain/weaversbrain/scripts/build_vault_index.py
```

- frontmatter + 파일명에서 date 추출
- `Projects/{프로젝트}/MOC.md` 자동 생성 (Obsidian 직접 탐색용, 44개 프로젝트)
- `~/.cache/weaversbrain-vault-index.json` 갱신 (현재 1711개 노트)

## 자동 갱신 (선택)

PostToolUse hook 으로 Vault 의 `.md` 편집 시 자동:

```json
// ~/.claude/settings.json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "~/.claude/skills/vault-find/scripts/ingest_hook.sh" }
        ]
      }
    ]
  }
}
```

또는 cron:
```bash
*/15 * * * * cd ~/Workspace/weaversbrain/weaversbrain && python3 scripts/build_vault_index.py --quiet
```

## 의존성

- Python 3.10+ (표준 라이브러리만)
- `rg` (ripgrep) — 없으면 풀텍스트 검색만 비활성, 메타 검색은 동작
- (선택) `mcp__local-rag` — 의미론 검색용. 4332 docs / 56115 chunks 이미 인덱싱

## 참고

- 인덱서: `~/Workspace/weaversbrain/weaversbrain/scripts/build_vault_index.py`
- MOC 파일: `Projects/{프로젝트}/MOC.md` — 자동 생성, 수동 편집 금지
- 의미론 검색: `mcp__local-rag__query_documents`
- 통합: `/morning` 의 4.3단계가 자동으로 최근 7일 노트 surface
