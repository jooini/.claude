#!/usr/bin/env zsh
set -u

JSON_OUT=""
JSON_OUT="$(/usr/bin/python3 /Users/leonard/.claude/scripts/llm-usage.py --json --days 1 2>/dev/null || true)"
[ -z "$JSON_OUT" ] && exit 0

/usr/bin/python3 - "$JSON_OUT" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
health = (payload.get("llm_adapter") or {}).get("health") or {}
overall = health.get("overall", "unknown")
if overall not in {"warning", "critical"}:
    sys.exit(0)

alerts = health.get("alerts") or []
parts = []
for alert in alerts:
    scope = alert.get("scope", "scope")
    name = alert.get("name", "")
    severity = alert.get("severity", "warning")
    err = float(alert.get("error_rate", 0.0)) * 100
    to = float(alert.get("timeout_rate", 0.0)) * 100
    avg = float(alert.get("avg_duration_ms", 0.0))
    reasons = ",".join(alert.get("reasons", [])) or "threshold"
    parts.append(f"{scope}:{name} {severity} err={err:.1f}% timeout={to:.1f}% avg={avg:.0f}ms reasons={reasons}")

message = "LLM adapter health " + overall
if parts:
    message += ": " + "; ".join(parts)
else:
    message += " (overall threshold exceeded)"

print(f"[llm-health] {message}", file=sys.stderr)
PY
exit 0
