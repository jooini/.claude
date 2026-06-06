#!/usr/bin/env bash
# 일일 보고서를 채팅/메일 붙여넣기용 포맷으로 변환하여 stdout + macOS 클립보드에 복사.
#
# 사용법:
#   ~/.claude/skills/write-daily-report/to-mattermost.sh [--plain|--report] [YYYY-MM-DD]
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
#
#   --report(팀 일일 업무 보고 메일/메신저 양식):
#     - 인사말("안녕하세요. / 기술개발연구실 {작성자}입니다. / 일일 업무 보고 드립니다.") + 맺음말("감사합니다.")
#     - `## 요약`          → `* 회고 및 공유 사항`
#     - `## 오늘 한 일`     → `* 오늘 한 일`
#     - `## 할 일`         → `* 내일 할 일`
#     - `## 이슈`/`## 확인 필요 사항` → 회고 및 공유 사항에 흡수(별도 섹션 안 만듦)
#     - `### 프로젝트` → 공백 6칸 `- `, 하위 `- ` 항목 → 공백 12칸 `- `
#     - 체크박스 마커(`[ ]`/`[x]`) 제거, 마크다운 전부 제거 (평문)
#     - 작성자/부서는 아래 REPORT_AUTHOR / REPORT_DEPT 로 지정 (env 로 덮어쓰기 가능)

set -eu

# ── 팀 보고 메일 양식 머리말 (--report 모드) ─────────────
REPORT_AUTHOR="${REPORT_AUTHOR:-주인식}"
REPORT_DEPT="${REPORT_DEPT:-기술개발연구실}"

PLAIN=0
REPORT=0
DATE=""

for arg in "$@"; do
    case "$arg" in
        --plain) PLAIN=1 ;;
        --report) REPORT=1 ;;
        *) DATE="$arg" ;;
    esac
done

DATE="${DATE:-$(date +%Y-%m-%d)}"
YEAR_MONTH="${DATE%-*}"
REPORT_FILE="$HOME/Workspace/weaversbrain/weaversbrain/Daily/${YEAR_MONTH}/${DATE}.md"

if [ ! -f "$REPORT_FILE" ]; then
    echo "❌ 보고서 없음: $REPORT_FILE" >&2
    exit 1
fi

if [ "$REPORT" -eq 1 ]; then
    # ── 팀 일일 업무 보고 메일/메신저 양식 (정현지 표준 양식) ──
    #
    # 들여쓰기 규칙(원본 정현지 보고서 실측):
    #   섹션 헤더(* ...) = 0칸
    #   1단계 항목 = 6칸 / 2단계 = 12칸 / 3단계 = 18칸  (단계당 6칸)
    #   ### 프로젝트 헤딩은 6칸 1단계 항목, 그 직속 - 는 12칸
    #   섹션 직속(### 없이 바로 오는) - 는 6칸
    #   항목 사이마다 빈 줄 1개
    #   이슈/확인필요 → 회고 및 공유 사항에 흡수 (오늘 한 일에 섞지 않음)
    BODY=$(
        awk '
            function emit(pad, text,    p) {
                if (printed) print ""        # 항목 사이 빈 줄 1개
                print pad "- " text
                printed = 1
            }
            BEGIN { in_fm = 0; fm_done = 0; cur = "skip"; printed = 0 }
            /^---$/ && !fm_done {
                if (in_fm) { fm_done = 1; in_fm = 0; next }
                else       { in_fm = 1; next }
            }
            in_fm { next }

            /^# 일일 업무 보고서[[:space:]]*$/ { next }

            # 섹션 매핑: ## 헤딩 → 보고 양식 섹션
            /^## / {
                t = substr($0, 4)
                if (t ~ /회고|공유|요약/) { cur = "recap";    print "* 회고 및 공유 사항"; printed = 0; next }
                if (t ~ /오늘 한 일/)     { cur = "today";    print ""; print "* 오늘 한 일"; printed = 0; next }
                if (t ~ /할 일/)          { cur = "tomorrow"; print ""; print "* 내일 할 일"; printed = 0; next }
                if (t ~ /이슈/)           { cur = "recap";    next }   # 이슈는 회고에 흡수
                if (t ~ /확인 필요/)      { cur = "recap";    next }
                cur = "skip"; next
            }
            cur == "skip" { next }

            # ### 프로젝트 헤딩 → 6칸 1단계 항목. 직속 - 는 한 단계(12칸) 더 깊게
            /^### / {
                title = substr($0, 5)
                gsub(/^\[(해결|미해결)\][[:space:]]*/, "", title)
                emit("      ", title)
                under_head = 1            # 다음 0칸 - 들은 이 프로젝트의 하위
                next
            }

            # - 불릿 항목 → 원본 공백 깊이로 레벨 환산
            {
                line = $0
                n = 0
                while (substr(line, n+1, 1) == " ") n++
                depth = int(n / 2)              # 원본 2칸 = 1단계
                sub(/^[[:space:]]*/, "", line)

                if (line ~ /^- /) {
                    sub(/^- \[[ xX]\][[:space:]]*/, "", line)   # 체크박스 마커 제거
                    sub(/^- /, "", line)
                    # ### 헤딩 직후의 항목들은 그 프로젝트 하위(+1단계). 헤딩 없이 오면 섹션 직속(6칸)
                    lvl = depth + (under_head ? 1 : 0)
                    if (lvl <= 0)       pad = "      "                  # 6칸
                    else if (lvl == 1)  pad = "            "            # 12칸
                    else if (lvl == 2)  pad = "                  "      # 18칸
                    else                pad = "                        " # 24칸
                    emit(pad, line)
                    next
                }
                next   # 빈 줄/기타 텍스트는 버림 (구조는 - 항목으로만)
            }
        ' "$REPORT_FILE" \
        | sed -E '
            s/\[\[([^]]+)\]\]/\1/g
            s/\[([^]]+)\]\([^)]+\)/\1/g
            s/!\[([^]]*)\]\([^)]+\)//g
            s/\*\*([^*]+)\*\*/\1/g
            s/__([^_]+)__/\1/g
            s/`([^`]+)`/\1/g
            s/~~([^~]+)~~/\1/g
            s/^---+$//
        '
    )
    OUTPUT=$(printf '안녕하세요.\n\n%s입니다.\n\n일일 업무 보고 드립니다.\n\n\n%s\n\n\n감사합니다.\n' \
        "${REPORT_DEPT} ${REPORT_AUTHOR}" "$BODY")
elif [ "$PLAIN" -eq 1 ]; then
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
        ' "$REPORT_FILE" \
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
        ' "$REPORT_FILE" \
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
    if [ "$REPORT" -eq 1 ]; then
        echo "✅ 클립보드 복사 완료 [report 모드: 팀 일일 업무 보고 메일 양식, 작성자 ${REPORT_AUTHOR}] ($(printf '%s' "$OUTPUT" | wc -l | tr -d ' ')줄)" >&2
    elif [ "$PLAIN" -eq 1 ]; then
        echo "✅ 클립보드 복사 완료 [plain 모드: 하이웍스/카톡/일반 텍스트용] ($(printf '%s' "$OUTPUT" | wc -l | tr -d ' ')줄)" >&2
    else
        echo "✅ 클립보드 복사 완료 [Mattermost 모드] ($(printf '%s' "$OUTPUT" | wc -l | tr -d ' ')줄)" >&2
    fi
fi
