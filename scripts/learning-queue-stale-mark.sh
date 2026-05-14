#!/usr/bin/env bash
# learning-queue-stale-mark.sh
# 학습 큐 (~/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md) 의
# 미정리 항목(- [ ])에 경과일별 마크를 자동으로 추가한다.
#
# 룰 (standard-routines.md 90일 룰 + 학습 큐 변형):
#   - 14일 경과: ⚠️ 14d 경과
#   - 30일 경과: ⚠️ 30d 경과 — 즉시 처리 또는 close 검토
#   - 90일 경과: 🔴 90d 경과 — 강등/삭제 후보
#   - 180일 경과: - [x] 로 자동 close + STALE: 180d 경과 자동 close
#
# 마크는 멱등 (이미 추가된 마크는 재추가 안 함).
# 실제 수정 시 .bak.YYYY-MM-DD-HHMM 백업 생성. 백업 7개 초과 시 가장 오래된 것 삭제.
#
# 사용법:
#   learning-queue-stale-mark.sh             # 실제 수정
#   learning-queue-stale-mark.sh --dry-run   # 미리보기만
#   learning-queue-stale-mark.sh -n          # 미리보기만

set -euo pipefail

QUEUE_FILE="${LEARNING_QUEUE_FILE:-$HOME/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md}"
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n)
            DRY_RUN=1
            ;;
        --help|-h)
            grep '^# ' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "알 수 없는 인자: $arg" >&2
            echo "사용법: $0 [--dry-run|-n]" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$QUEUE_FILE" ]]; then
    echo "[오류] 학습 큐 파일을 찾을 수 없음: $QUEUE_FILE" >&2
    exit 1
fi

TODAY_EPOCH=$(date +%s)
TODAY_HHMM=$(date +%Y-%m-%d-%H%M)

MARK_14="⚠️ 14d 경과"
MARK_30="⚠️ 30d 경과 — 즉시 처리 또는 close 검토"
MARK_90="🔴 90d 경과 — 강등/삭제 후보"
MARK_180="STALE: 180d 경과 자동 close"

# 실제 모드면 변경이 있을 경우에만 백업할 수 있도록, 먼저 dry-run 형태로 변경 여부를 판단한다.
# Python 스크립트는 인자로 dry_run 여부를 받고, 변경 사항 출력 + 변경 카운트를 반환한다.

run_python() {
    local mode="$1"  # "dry" or "apply"
    python3 - "$QUEUE_FILE" "$TODAY_EPOCH" "$mode" "$MARK_14" "$MARK_30" "$MARK_90" "$MARK_180" <<'PYEOF'
import sys
import re
from datetime import datetime

queue_path = sys.argv[1]
today_epoch = int(sys.argv[2])
mode = sys.argv[3]  # "dry" or "apply"
MARK_14 = sys.argv[4]
MARK_30 = sys.argv[5]
MARK_90 = sys.argv[6]
MARK_180 = sys.argv[7]

with open(queue_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

date_re = re.compile(r'^(- \[ \] \*\*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\*\*)(.*)$')

stats = {
    "scanned": 0,
    "marked_14": 0,
    "marked_30": 0,
    "marked_90": 0,
    "closed_180": 0,
    "untouched": 0,
}
changes = []

for i, line in enumerate(lines):
    m = date_re.match(line.rstrip("\n"))
    if not m:
        continue
    stats["scanned"] += 1
    ymd, hm = m.group(2), m.group(3)
    try:
        item_dt = datetime.strptime(f"{ymd} {hm}", "%Y-%m-%d %H:%M")
    except ValueError:
        continue
    age_days = (today_epoch - int(item_dt.timestamp())) // 86400

    new_line = line.rstrip("\n")
    changed = False

    if age_days >= 180:
        if MARK_180 not in new_line:
            new_line = new_line.replace("- [ ]", "- [x]", 1)
            new_line = f"{new_line} {MARK_180}"
            stats["closed_180"] += 1
            changed = True
    else:
        if age_days >= 90 and MARK_90 not in new_line:
            new_line = f"{new_line} {MARK_90}"
            stats["marked_90"] += 1
            changed = True
        if age_days >= 30 and MARK_30 not in new_line:
            new_line = f"{new_line} {MARK_30}"
            stats["marked_30"] += 1
            changed = True
        if age_days >= 14 and MARK_14 not in new_line:
            new_line = f"{new_line} {MARK_14}"
            stats["marked_14"] += 1
            changed = True

    if changed:
        changes.append((i + 1, line.rstrip("\n"), new_line, age_days))
        lines[i] = new_line + "\n"
    else:
        stats["untouched"] += 1

print(f"[학습 큐] {queue_path}")
print(f"[모드] {'DRY-RUN (미리보기)' if mode == 'dry' else '실제 수정'}")
print(f"[스캔] 미정리(- [ ]) 항목: {stats['scanned']}개")
print(f"[변경] 14d 마크: {stats['marked_14']} / 30d 마크: {stats['marked_30']} / 90d 마크: {stats['marked_90']} / 180d 자동 close: {stats['closed_180']}")
print(f"[보존] 변경 없음: {stats['untouched']}")

if changes:
    print("")
    print("=== 변경 상세 ===")
    for ln, before, after, age in changes:
        print(f"L{ln} (age={age}d)")
        print(f"  - {before}")
        print(f"  + {after}")
else:
    print("")
    print("[정보] 마크/close 대상 항목 없음.")

# 종료 코드: 변경 건수
# (백업 필요 여부 판단을 위해 호출 측에서 활용)
total_changes = len(changes)

if mode == "apply" and total_changes > 0:
    with open(queue_path, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("")
    print(f"[완료] 파일 갱신됨: {queue_path}")

# 종료 코드는 0 (성공). 변경 건수는 별도 stderr 채널로 전달.
sys.stderr.write(f"__CHANGE_COUNT__={total_changes}\n")
PYEOF
}

backup_cleanup() {
    local dir base count to_delete
    dir="$(dirname "$QUEUE_FILE")"
    base="$(basename "$QUEUE_FILE")"
    local backups=()
    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -1tr "$dir"/"$base".bak.* 2>/dev/null || true)
    count=${#backups[@]}
    if (( count > 7 )); then
        to_delete=$(( count - 7 ))
        for ((i=0; i<to_delete; i++)); do
            echo "[백업 정리] 삭제: ${backups[$i]}"
            rm -f "${backups[$i]}"
        done
    fi
}

if [[ "$DRY_RUN" -eq 1 ]]; then
    # dry-run: 그냥 출력만
    run_python "dry" 2>/dev/null
    exit 0
fi

# 실제 모드:
# 1) 먼저 dry로 변경 건수 판단
TMP_STDERR=$(mktemp)
run_python "dry" 2>"$TMP_STDERR" >/dev/null
CHANGE_COUNT=$(grep -E '^__CHANGE_COUNT__=' "$TMP_STDERR" | tail -1 | sed 's/^__CHANGE_COUNT__=//')
rm -f "$TMP_STDERR"
CHANGE_COUNT="${CHANGE_COUNT:-0}"

if [[ "$CHANGE_COUNT" -gt 0 ]]; then
    BACKUP_FILE="${QUEUE_FILE}.bak.${TODAY_HHMM}"
    cp -p "$QUEUE_FILE" "$BACKUP_FILE"
    echo "[백업] 생성됨: $BACKUP_FILE"
fi

# 2) 실제 적용
run_python "apply" 2>/dev/null

# 3) 백업 정리
if [[ "$CHANGE_COUNT" -gt 0 ]]; then
    backup_cleanup
fi
