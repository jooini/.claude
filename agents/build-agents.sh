#!/bin/zsh
# build-agents.sh — knowledge를 압축하여 에이전트 프롬프트에 삽입
#
# 사용법:
#   ./build-agents.sh                          # 전체 빌드 (CWD에서 언어 자동 감지)
#   ./build-agents.sh backend-developer        # 특정 에이전트만
#   ./build-agents.sh --lang python            # 언어 지정
#   ./build-agents.sh --full                   # 압축 없이 전체 삽입
#   ./build-agents.sh --dry-run                # 미리보기
#   ./build-agents.sh --use python             # 빌드 없이 심볼릭 링크만 전환
#   ./build-agents.sh --list                   # 빌드된 언어 목록
#
# 기본 동작:
#   1. CWD의 프로젝트 파일로 언어 자동 감지
#   2. 루트 knowledge → 헤더+불릿+테이블만 추출 (코드블록/설명 제거)
#   3. 감지된 언어의 하위 knowledge만 포함 (나머지 언어 제외)
#   4. builds/{lang}/ 에 출력 후 심볼릭 링크로 활성화

set -euo pipefail

AGENTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$(dirname "$AGENTS_DIR")/agents-src"
BUILDS_DIR="$AGENTS_DIR/builds"

DRY_RUN=false
FULL_MODE=false
NO_KNOWLEDGE=false
OUT_SUFFIX=""
TARGET=""
LANG_OVERRIDE=""
USE_LANG=""
LIST_MODE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --full) FULL_MODE=true ;;
    --no-knowledge) NO_KNOWLEDGE=true; OUT_SUFFIX="-nokb" ;;
    --lang) shift_next=true ;;
    --use) use_next=true ;;
    --list) LIST_MODE=true ;;
    *)
      if [ "${shift_next:-}" = true ]; then
        LANG_OVERRIDE="$arg"
        shift_next=false
      elif [ "${use_next:-}" = true ]; then
        USE_LANG="$arg"
        use_next=false
      else
        TARGET="$arg"
      fi
      ;;
  esac
done

# --lang 값 파싱 (--lang=python 형태도 지원)
for arg in "$@"; do
  case "$arg" in
    --lang=*) LANG_OVERRIDE="${arg#--lang=}" ;;
    --use=*) USE_LANG="${arg#--use=}" ;;
    --lang)
      # 다음 인자가 언어
      found_lang=false
      for a in "$@"; do
        if [ "$found_lang" = true ]; then
          LANG_OVERRIDE="$a"
          break
        fi
        [ "$a" = "--lang" ] && found_lang=true
      done
      ;;
    --use)
      found_use=false
      for a in "$@"; do
        if [ "$found_use" = true ]; then
          USE_LANG="$a"
          break
        fi
        [ "$a" = "--use" ] && found_use=true
      done
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo "${GREEN}[BUILD]${NC} $1" }
warn() { echo "${YELLOW}[WARN]${NC} $1" }
info() { echo "${CYAN}[INFO]${NC} $1" }

# 심볼릭 링크 활성화
activate_lang() {
  local lang="$1"
  local build_dir="$BUILDS_DIR/$lang"

  if [ ! -d "$build_dir" ]; then
    echo "${RED}[ERROR]${NC} 빌드 없음: $build_dir"
    echo "  사용 가능: $(ls "$BUILDS_DIR" 2>/dev/null | tr '\n' ' ')"
    exit 1
  fi

  # 기존 심볼릭 링크 제거
  for f in "$AGENTS_DIR"/*.md; do
    [ -L "$f" ] && rm "$f"
  done

  # 새 심볼릭 링크 생성
  local count=0
  for f in "$build_dir"/*.md; do
    [ -f "$f" ] || continue
    local name=$(basename "$f")
    ln -s "$f" "$AGENTS_DIR/$name"
    count=$((count + 1))
  done

  log "활성화: ${lang} (${count}개 에이전트)"
}

# --list: 빌드된 언어 목록
if [ "$LIST_MODE" = true ]; then
  echo ""
  info "빌드된 언어 목록:"
  if [ -d "$BUILDS_DIR" ]; then
    for d in "$BUILDS_DIR"/*/; do
      [ -d "$d" ] || continue
      lang_name=$(basename "$d")
      count=$(ls "$d"/*.md 2>/dev/null | wc -l | tr -d ' ')
      active=""
      # 현재 활성 확인: 아무 에이전트 하나의 심볼릭 링크가 이 디렉토리를 가리키는지
      for candidate in "$d"/*.md; do
        [ -f "$candidate" ] || continue
        candidate_name=$(basename "$candidate")
        agent_link="$AGENTS_DIR/$candidate_name"
        if [ -L "$agent_link" ]; then
          link_target=$(readlink "$agent_link")
          # 절대경로로 비교
          real_candidate=$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")
          if [ "$link_target" = "$real_candidate" ]; then
            active=" ← 활성"
          fi
        fi
        break
      done
      echo "  ${lang_name}: ${count}개${active}"
    done
  else
    warn "빌드 디렉토리 없음"
  fi
  echo ""
  exit 0
fi

# --use: 심볼릭 링크만 전환
if [ -n "$USE_LANG" ]; then
  activate_lang "$USE_LANG"
  exit 0
fi

# 프로젝트 언어 자동 감지
detect_language() {
  local dir="${1:-.}"

  if [ -n "$LANG_OVERRIDE" ]; then
    echo "$LANG_OVERRIDE"
    return
  fi

  # CWD에서 감지
  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/requirements.txt" ] || [ -f "$dir/Pipfile" ]; then
    echo "python"
  elif [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] || [ -f "$dir/pom.xml" ]; then
    echo "kotlin"
  elif [ -f "$dir/composer.json" ]; then
    echo "php"
  elif [ -f "$dir/package.json" ]; then
    echo "nodejs"
  elif [ -f "$dir/go.mod" ]; then
    echo "go"
  elif [ -f "$dir/Cargo.toml" ]; then
    echo "rust"
  else
    echo ""
  fi
}

# knowledge 파일 1개를 압축
# H1 제거, H3는 보존(카운터 리셋), H4+ 제거
# 안티패턴 섹션 불릿 무제한, 그 외 섹션당 MAX_BULLETS개
# 볼드체 포함 일반 문장도 보존
compress_knowledge() {
  local file="$1"

  awk '
    BEGIN { in_code=0; in_front=0; front_done=0; bullet_count=0; MAX_BULLETS=8; is_anti=0 }

    # frontmatter 제거
    /^---$/ && !front_done {
      if (in_front) { front_done=1; next }
      else { in_front=1; next }
    }
    in_front && !front_done { next }

    # 원본 링크 줄 제거
    /^> 원본:/ { next }

    # 코드 블록 건너뛰기
    /^```/ { in_code = !in_code; next }
    in_code { next }

    # 빈 줄은 하나만 유지
    /^[[:space:]]*$/ { if (prev_blank) next; prev_blank=1; print; next }
    { prev_blank=0 }

    # H1 제거 (파일 제목 — concat_knowledge가 이미 추가)
    /^# [^#]/ { next }

    # H2: 출력 + 안티패턴 체크 + 카운터 리셋
    /^## / {
      bullet_count=0
      is_anti = ($0 ~ /안티패턴/ || $0 ~ /[Aa]nti-?[Pp]attern/)
      print; next
    }

    # H3: 보존 (컨텍스트 유지) + 카운터 리셋
    /^### / { bullet_count=0; print; next }

    # H4+: 제거
    /^####+ / { next }

    # 테이블: 항상 출력
    /^\| / { print; next }

    # 불릿/리스트
    /^- / || /^\* / || /^[0-9]+\. / {
      if (is_anti) { print; next }
      bullet_count++
      if (bullet_count <= MAX_BULLETS) { print }
      else if (bullet_count == MAX_BULLETS + 1) { print "- ..." }
      next
    }

    # 인용
    /^> / { print; next }

    # 볼드체 파일 제목 구분자: 안티패턴 플래그 + 카운터 리셋
    /^\*\*.+\*\*$/ { is_anti=0; bullet_count=0; print; next }

    # 볼드체 포함 일반 문장 보존
    /\*\*.+\*\*/ { print; next }

    # 나머지는 제거
  ' "$file"
}

# knowledge 전체 삽입 (압축 없음)
inline_full() {
  local file="$1"
  awk '
    BEGIN { in_front=0; front_done=0 }
    /^---$/ && !front_done {
      if (in_front) { front_done=1; next }
      else { in_front=1; next }
    }
    !in_front || front_done { print }
  ' "$file"
}

# knowledge 디렉토리 처리
concat_knowledge() {
  local knowledge_dir="$1"
  local label="$2"
  local detected_lang="$3"

  if [ ! -d "$knowledge_dir" ]; then
    info "Role knowledge 디렉토리 없음 (회사 공통만 포함): $knowledge_dir"
    # 회사 공통은 그래도 출력하므로 return 안 함
  fi

  local mode_label="압축"
  [ "$FULL_MODE" = true ] && mode_label="전체"

  echo ""
  echo "---"
  echo ""
  echo "## Knowledge Reference (${mode_label})"
  echo ""
  # 회사 공통 knowledge 자동 포함 (모든 role 공통)
  local company_dir="$AGENTS_DIR/knowledge/_company"
  if [ -d "$company_dir" ]; then
    echo "### Company-wide (사내 공통)"
    echo ""
    for f in "$company_dir"/*.md(N); do
      echo "**$(basename "${f%.md}")**"
      echo ""
      if [ "$FULL_MODE" = true ]; then
        cat "$f"
      else
        # 압축: 헤더 + 불릿 + 표만
        awk '/^#+ |^[*-] |^\| /' "$f"
      fi
      echo ""
    done
    echo "### Role-specific"
    echo ""
  fi
  if [ "$FULL_MODE" = false ]; then
    echo "> 핵심 규칙만 포함. 상세 내용은 \`~/.claude/agents/${label}/\` 에서 Read 가능."
  else
    echo "> 빌드 시 자동 삽입된 knowledge 문서."
  fi
  echo ""

  # 파일 수집: 루트 먼저 등록, 언어 변종으로 덮어쓰기 (zsh 연관 배열)
  local -A target_files

  for f in "$knowledge_dir"/*.md(N); do
    target_files[${f:t}]="$f"
  done

  if [[ -n "$detected_lang" && -d "$knowledge_dir/$detected_lang" ]]; then
    for f in "$knowledge_dir/$detected_lang"/*.md(N); do
      target_files[${f:t}]="$f"
    done
  fi

  # 파일명 순서대로 정렬하여 출력
  for filename in ${(ok)target_files}; do
    local f=$target_files[$filename]
    local title=$(echo "$filename" | sed 's/\.md$//;s/^[0-9]*-//')
    local is_lang_variant=false
    [[ "$f" == *"/$detected_lang/"* ]] && is_lang_variant=true

    local suffix=""
    [[ "$is_lang_variant" = true ]] && suffix=" (${detected_lang})"

    if [[ "$FULL_MODE" == "true" ]]; then
      echo "### ${title}${suffix}"
      echo ""
      inline_full "$f"
    else
      echo "**${title}**${suffix}"
      compress_knowledge "$f"
    fi
    echo ""
  done
}

# 공통 블록 삽입 (BUILD:COMMON 처리)
inline_common() {
  local common_path="$1"
  local full_path="$AGENTS_DIR/$common_path"

  if [ ! -f "$full_path" ]; then
    warn "공통 블록 없음: $full_path"
    return
  fi

  cat "$full_path"
}

# src 파일의 BUILD 마커를 모두 처리하여 tmp 파일에 기록
process_markers() {
  local src_file="$1"
  local detected_lang="$2"
  local out="$3"

  while IFS= read -r line; do
    if echo "$line" | grep -q '<!-- BUILD:COMMON'; then
      local common_path=$(echo "$line" | sed 's/.*BUILD:COMMON \([^ ]*\) .*/\1/')
      inline_common "$common_path" >> "$out"
    elif echo "$line" | grep -q '<!-- BUILD:KNOWLEDGE'; then
      if [ "$NO_KNOWLEDGE" = true ]; then
        : # knowledge 섹션 완전히 생략 (A/B ablation 검증용)
      else
        local knowledge_path=$(echo "$line" | sed 's/.*BUILD:KNOWLEDGE \([^ ]*\) .*/\1/')
        local full_knowledge_path="$AGENTS_DIR/$knowledge_path"
        concat_knowledge "$full_knowledge_path" "$knowledge_path" "$detected_lang" >> "$out"
      fi
    else
      echo "$line" >> "$out"
    fi
  done < "$src_file"
}

# 에이전트 빌드
build_agent() {
  local src_file="$1"
  local detected_lang="$2"
  local out_dir="$3"
  local agent_name=$(basename "$src_file" .md)
  local out_file="$out_dir/${agent_name}.md"

  info "빌드 중: ${agent_name}"

  local has_markers=$(grep -c '<!-- BUILD:' "$src_file" 2>/dev/null || true)

  if [ "$has_markers" -eq 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      info "  ${agent_name}: $(wc -l < "$src_file") lines (마커 없음)"
    else
      cp "$src_file" "$out_file"
      log "  ${agent_name}: 복사 완료"
    fi
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    local tmp=$(mktemp)
    process_markers "$src_file" "$detected_lang" "$tmp"
    local total=$(wc -l < "$tmp")
    rm -f "$tmp"
    local mode="압축"
    [ "$FULL_MODE" = true ] && mode="전체"
    local lang_info="${detected_lang:-없음}"
    info "  ${agent_name}: ${total} lines (${mode}, lang=${lang_info})"
    return
  fi

  local tmp_file=$(mktemp)
  process_markers "$src_file" "$detected_lang" "$tmp_file"

  # 후처리: 빈 헤더 제거 + 연속 빈 줄 압축
  # 단, ## 헤더는 ### 헤더가 와도 부모-자식 관계이므로 보존
  local clean_file=$(mktemp)
  awk '
    # H2 헤더는 항상 보존 (### 자식이 와도 부모로서 의미 있음)
    /^## [^#]/ {
      if (header != "") { print header; print "" }
      print $0
      header = ""
      blank_after = 0
      next
    }
    # H3+ 헤더 버퍼링: 다음 비빈 줄이 또 H3+ 헤더이면 이전 헤더는 빈 헤더 → 제거
    /^###+ / {
      if (header != "") {
        # 이전 헤더 뒤에 내용 없이 새 헤더 → 이전 헤더 버림
      }
      header = $0
      blank_after = 0
      next
    }
    /^[[:space:]]*$/ {
      if (header != "") { blank_after++; next }
      # 연속 빈 줄 최대 1개
      if (prev_blank) next
      prev_blank = 1
      print
      next
    }
    {
      # 내용 있는 줄 → 버퍼된 헤더 출력
      if (header != "") {
        print header
        for (i = 0; i < blank_after && i < 1; i++) print ""
        header = ""
        blank_after = 0
      }
      prev_blank = 0
      print
    }
    END {
      # 마지막 헤더가 내용 없이 끝나면 버림
    }
  ' "$tmp_file" > "$clean_file"
  rm -f "$tmp_file"

  mv "$clean_file" "$out_file"
  local total_lines=$(wc -l < "$out_file")
  log "  ${agent_name}: ${total_lines} lines"
}

# 메인
DETECTED_LANG=$(detect_language)

# 빌드 출력 디렉토리 결정
LANG_LABEL="${DETECTED_LANG:-root}"
OUT_DIR="$BUILDS_DIR/$LANG_LABEL"

echo ""
echo "========================================="
echo "  Agent Knowledge Builder"
echo "========================================="
echo ""
info "언어 감지: ${DETECTED_LANG:-없음 (루트 knowledge만 포함)}"
info "출력: builds/${LANG_LABEL}/"
info "모드: $([ "$FULL_MODE" = true ] && echo '전체 삽입' || echo '압축 (헤더+불릿+테이블)')"
[ "$DRY_RUN" = true ] && warn "DRY RUN"
echo ""

# 빌드 디렉토리 생성
[ "$DRY_RUN" = false ] && mkdir -p "$OUT_DIR"

if [ -n "$TARGET" ] && [ "$TARGET" != "--dry-run" ] && [ "$TARGET" != "--full" ]; then
  src="$SRC_DIR/${TARGET}.md"
  if [ ! -f "$src" ]; then
    echo "${RED}[ERROR]${NC} 템플릿 없음: $src"
    exit 1
  fi
  build_agent "$src" "$DETECTED_LANG" "$OUT_DIR"
else
  for src in "$SRC_DIR"/*.md; do
    [ -f "$src" ] || continue
    build_agent "$src" "$DETECTED_LANG" "$OUT_DIR"
  done
fi

# 빌드 완료 후 심볼릭 링크 활성화
if [ "$DRY_RUN" = false ]; then
  activate_lang "$LANG_LABEL"
fi

echo ""
log "완료!"
echo ""
