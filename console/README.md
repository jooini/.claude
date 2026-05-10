# Workspace Console

1인 개발자용 관제탑 CLI. 95+ hooks, 93+ skills, 13+ agents, 14+ commands, 110+ repo 통합 인덱스.

## 명령

| 명령 | 설명 |
|------|------|
| `wsq sweep` | 모든 repo vitality 측정 → 콘솔 표 + JSON 리포트 |
| `wsq report <json> <md>` | sweep JSON → 사용자 검토 마크다운 (체크박스 포함) |
| `wsq archive <md>` | 사용자가 `[x] archive` 체크한 repo 일괄 이동 (dry-run 기본) |
| `wsq triage <md>` | 미커밋 4 카테고리 분류 (commit_ready/delete/experiment/unknown) |
| `wsq cleanup <md>` | commit_ready 일괄 커밋 + delete 일괄 삭제 (dry-run 기본) |
| `wsq compare <a.json> <b.json>` | 두 sweep JSON diff (신규 dead/zombie/부활) |
| `wsq index` | 전체 catalog 재인덱싱 (5초, repos 포함) |
| `wsq refresh` | quick incremental — hooks/skills/agents/commands만 (1초 미만) |
| `wsq refresh --no-quick` | 전체 재인덱싱 (index 와 동일) |
| `wsq search <query>` | catalog FTS5 검색 (한글 토큰 지원) |

### 검색 옵션

```bash
wsq search debug                  # 모든 type
wsq search debug --type skill     # skill 만
wsq search hook --broken          # 부서진 부품 포함
wsq search wsq -l 50              # 50개까지
```

## 자동화 (선택)

SessionStart 마다 catalog 자동 갱신:

```json
// ~/.claude/settings.json hooks 섹션
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"command": "$HOME/.claude/hooks/SessionStart/wsq-catalog-refresh.sh"}]}
    ]
  }
}
```

스크립트는 백그라운드(`nohup &`) 실행 → SessionStart latency 0.

로그: `~/.claude/logs/wsq-catalog-refresh.log`

## catalog.db 구조

- 위치: `~/.claude/console/catalog.db`
- SQLite 3 + FTS5 (한글 unicode61 토큰)
- 단일 `entity` 테이블 — type 으로 6종 구분 (hook/skill/agent/command/repo/mcp)
- `metadata_json` 으로 type 별 추가 정보 저장 (mtime, event, frontmatter 등)
- WAL 모드 (동시 읽기/쓰기 허용)

## Phase 1 종료 상태

- 324+ entity 인덱싱 (hooks 95 + skills 93 + agents 13 + commands 14 + repos 110)
- 70 테스트 (TDD 기반)
- catalog.db FTS5 한글 토큰 지원
- incremental update + SessionStart hook script (settings.json 등록은 사용자 결정)

## 개발

```bash
cd ~/.claude/console
source .venv/bin/activate
pytest -v        # 70 passed
wsq --help
```
