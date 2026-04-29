#!/usr/bin/env bash
# 일일 보고서를 채팅 붙여넣기용 포맷으로 변환하여 stdout + macOS 클립보드에 복사.
#
# 사용법:
#   ~/.claude/skills/write-daily-report/to-mattermost.sh [--plain] [YYYY-MM-DD]
#     (날짜 생략 시 오늘)
#
# 모드:
#   default(Mattermost):
#     - `## 제목` → ■ 제목 + 구분선
#     - `### 제목` → ▸ 제목
#     - `-` → •
#     - `[[link]]` 대괄호 제거
#     - 백틱 유지(Mattermost는 inline code 지원)
#
#   --plain(하이웍스·카톡·일반 텍스트):
#     - 모든 마크다운 문법 완전 제거 (백틱, **bold**, *italic*, ~~strike~~, [text](url), 이미지)
#     - 헤딩은 prefix로만 (▣ / ▸)
#     - 문단 간 빈 줄 2개 (일부 에디터가 싱글 개행을 무시)
#     - 체크박스 `- [ ]` → □, `- [x]` → ■
#     - bullet `-` → · (중점, 더 가벼운 기호)

set -eu

PLAIN=0
DATE=""

for arg in "$@"; do
    case "$arg" in
        --plain) PLAIN=1 ;;
        *) DATE="$arg" ;;
    esac
done

DATE="${DATE:-$(date +%Y-%m-%d)}"
YEAR_MONTH="${DATE%-*}"
REPORT="$HOME/Workspace/weaversbrain/weaversbrain/Daily/${YEAR_MONTH}/${DATE}.md"

if [ ! -f "$REPORT" ]; then
    echo "❌ 보고서 없음: $REPORT" >&2
    exit 1
fi

if [ "$PLAIN" -eq 1 ]; then
    OUTPUT=$(
        awk '
            BEGIN { in_fm = 0; fm_done = 0 }
            /^---$/ && !fm_done {
                if (in_fm) { fm_done = 1; in_fm = 0; next }
                else       { in_fm = 1; next }
            }
            in_fm { next }

            /^# 일일 업무 보고서[[:space:]]*$/ { next }

            /^## / {
                title = substr($0, 4)
                print ""
                print ""
                print "▣ " title
                print ""
                next
            }

            /^### / {
                title = substr($0, 5)
                print ""
                print "▸ " title
                next
            }

            /^- \[ \] / { sub(/^- \[ \] /, "□ "); print; next }
            /^- \[x\] / { sub(/^- \[x\] /, "■ "); print; next }
            /^- \[X\] / { sub(/^- \[X\] /, "■ "); print; next }

            /^- / { sub(/^- /, "· "); print; next }

            { print }
        ' "$REPORT" \
        | sed -E '
            # Obsidian 링크 대괄호 제거
            s/\[\[([^]]+)\]\]/\1/g
            # 표준 마크다운 링크 [text](url) → text
            s/\[([^]]+)\]\([^)]+\)/\1/g
            # 이미지 ![alt](url) → alt
            s/!\[([^]]*)\]\([^)]+\)//g
            # 볼드/이탤릭 제거
            s/\*\*([^*]+)\*\*/\1/g
            s/__([^_]+)__/\1/g
            s/\*([^*]+)\*/\1/g
            s/_([^_]+)_/\1/g
            # 취소선 제거
            s/~~([^~]+)~~/\1/g
            # inline 코드 백틱 제거
            s/`([^`]+)`/\1/g
            # 블록 코드 펜스 제거
            s/^```[a-zA-Z0-9_+-]*$//
            s/^```$//
            # 수평선 제거
            s/^---+$//
        ' \
        | awk '
            # 싱글 개행 문단을 살리기 위해 빈 줄 2개까지 허용
            /^[[:space:]]*$/ { blank++; if (blank <= 2) print; next }
            { blank = 0; print }
        '
    )
else
    OUTPUT=$(
        awk '
            BEGIN { in_fm = 0; fm_done = 0 }
            /^---$/ && !fm_done {
                if (in_fm) { fm_done = 1; in_fm = 0; next }
                else       { in_fm = 1; next }
            }
            in_fm { next }

            /^# 일일 업무 보고서[[:space:]]*$/ { next }

            /^## / {
                title = substr($0, 4)
                print ""
                print "■ " title
                print "────────────────────"
                next
            }

            /^### / {
                title = substr($0, 5)
                print ""
                print "▸ " title
                next
            }

            /^- \[ \] / { sub(/^- \[ \] /, "• [ ] "); print; next }
            /^- \[x\] / { sub(/^- \[x\] /, "• [x] "); print; next }
            /^- \[X\] / { sub(/^- \[X\] /, "• [x] "); print; next }

            /^- / { sub(/^- /, "• "); print; next }

            { print }
        ' "$REPORT" \
        | sed -E 's/\[\[([^]]+)\]\]/\1/g' \
        | awk '
            /^[[:space:]]*$/ { blank++; if (blank <= 1) print; next }
            { blank = 0; print }
        '
    )
fi

printf '%s\n' "$OUTPUT"

if command -v pbcopy >/dev/null 2>&1; then
    printf '%s\n' "$OUTPUT" | pbcopy
    echo "" >&2
    if [ "$PLAIN" -eq 1 ]; then
        echo "✅ 클립보드 복사 완료 [plain 모드: 하이웍스/카톡/일반 텍스트용] ($(printf '%s' "$OUTPUT" | wc -l | tr -d ' ')줄)" >&2
    else
        echo "✅ 클립보드 복사 완료 [Mattermost 모드] ($(printf '%s' "$OUTPUT" | wc -l | tr -d ' ')줄)" >&2
    fi
fi
