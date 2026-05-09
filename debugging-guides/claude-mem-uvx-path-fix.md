# claude-mem MCP "Executable not found in $PATH: uvx" 복구 가이드

**증상**: Claude Code에서 `mcp__plugin_claude-mem_mcp-search__*` 도구 호출 시
```
Error calling Worker API: Worker API error (500): {"error":"Executable not found in $PATH: \"uvx\""}
```
또는 비슷하게 `chroma-mcp` spawn 실패.

## 빠른 진단

```bash
# 1. uvx 설치 자체는 멀쩡한지
which uvx
# /opt/homebrew/bin/uvx (정상)

# 2. claude-mem worker 데몬 PID
cat ~/.claude-mem/worker.pid

# 3. 그 PID의 환경변수 PATH 확인 (macOS)
ps -p {pid} -E | tr ' ' '\n' | grep ^PATH=
```

worker PATH에 `/opt/homebrew/bin` 이 **없으면** 이 가이드 적용.

## 원인

claude-mem worker는 detached daemon (ppid=1). 한 번 spawn되면 그 시점의 환경변수를 유지함. 이전에 PATH가 깨진 상태로 spawn됐다면 settings.json `env.PATH`를 고쳐도 기존 데몬에는 무영향.

worker는 chroma-mcp를 stdio로 spawn하는데 `command: "uvx"`로 호출 (worker-service.cjs에 하드코딩). 따라서 worker 자체 PATH에 `/opt/homebrew/bin`이 있어야 함.

## 복구

```bash
cd ~/.claude/plugins/cache/thedotmack/claude-mem/10.6.2
node scripts/bun-runner.js scripts/worker-cli.js stop
```

worker가 죽으면 다음 SessionStart hook 또는 자동 재기동 로직이 새 worker를 spawn함. 이때 새 worker는 settings.json `env.PATH` (이미 `/opt/homebrew/bin` 포함)를 상속.

검증:
```bash
# 새 PID로 PATH 재확인
cat ~/.claude-mem/worker.pid
ps -p {새 pid} -E | tr ' ' '\n' | grep ^PATH=

# uvx 호출 검증 (worker → chroma-mcp)
curl -s "http://127.0.0.1:37777/api/search?query=test&limit=1"
```

## 예방

`~/.claude/settings.json`의 `env.PATH`에 `/opt/homebrew/bin` 이 들어 있는지 확인. 들어 있으면 다음 worker spawn부터는 자동 적용.

## 관련 incidents

- 2026-05-10: Workspace Console Phase 0 Task 1
  - Vault: `2026-05-10-0125-claude-mem-mcp-uvx-path-fix.md`
