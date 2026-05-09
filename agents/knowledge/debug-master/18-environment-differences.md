# 환경 차이 분석

> "내 컴퓨터에선 됐다"는 결론이 아니라 환경 차이를 찾으라는 신호다.

---

## 1. 환경 차이가 만드는 버그

환경 차이는 코드가 같아도 실행 결과를 바꾼다.
로컬, CI, 스테이징, 운영의 차이를 명시적으로 비교해야 한다.

주요 차이:

- [ ] 환경변수
- [ ] 런타임 버전
- [ ] dependency lockfile
- [ ] OS와 CPU architecture
- [ ] timezone과 locale
- [ ] DB schema/data
- [ ] network/proxy
- [ ] feature flag
- [ ] 권한과 파일 시스템

---

## 2. 환경 스냅샷

```bash
{
    date -Is
    uname -a
    pwd
    node --version 2>/dev/null || true
    npm --version 2>/dev/null || true
    python --version 2>/dev/null || true
    pip --version 2>/dev/null || true
    env | sort
} > /tmp/environment-snapshot.txt
```

환경변수에는 비밀값이 포함될 수 있다.
공유 전 마스킹한다.

---

## 3. 환경변수 비교

```bash
comm -3 \
    <(sed -E 's/=.*/=***/' /tmp/local-env.txt | sort) \
    <(sed -E 's/=.*/=***/' /tmp/staging-env.txt | sort)
```

값 자체가 필요한 경우에도 secret은 제외한다.
boolean flag, URL host, timeout, timezone처럼 동작에 영향을 주는 값부터 비교한다.

---

## 4. Dependency 차이

```bash
npm ci
npm ls --depth=0 > /tmp/npm-tree.txt
```

```bash
pip freeze | sort > /tmp/pip-freeze.txt
```

확인할 것:

- [ ] lockfile이 커밋되었는가?
- [ ] CI가 lockfile 기반 설치를 하는가?
- [ ] optional dependency가 OS별로 달라지는가?
- [ ] native module rebuild가 필요한가?
- [ ] transitive dependency가 바뀌었는가?

---

## 5. Runtime 버전

```bash
node -p "process.versions"
python - <<'PY'
import platform
import sys
print(sys.version)
print(platform.platform())
PY
```

Node, Python, JVM minor version 차이도 동작을 바꿀 수 있다.
특히 URL parsing, timezone database, TLS 기본값, OpenSSL 버전은 자주 문제를 만든다.

---

## 6. Timezone과 locale

```bash
date
date -u
echo "TZ=${TZ:-unset}"
locale
```

```python
from datetime import datetime
from zoneinfo import ZoneInfo

print(datetime.now())
print(datetime.now(ZoneInfo("Asia/Seoul")))
```

날짜 버그는 환경별 timezone이 다를 때 재현된다.
서버는 UTC, 사용자 표시는 명시 timezone으로 처리하는 원칙이 안전하다.

---

## 7. OS와 파일 시스템

| 차이 | 영향 |
|------|------|
| 대소문자 구분 | macOS에서 통과, Linux에서 실패 |
| 경로 separator | Windows path 처리 실패 |
| 파일 권한 | 컨테이너에서 write 실패 |
| line ending | script 실행 실패 |
| architecture | native binary 불일치 |

```bash
git ls-files | awk '{ print tolower($0) }' | sort | uniq -d
find scripts -type f -maxdepth 2 -print0 | xargs -0 file
```

---

## 8. DB schema와 seed 차이

```bash
psql "$DATABASE_URL" -c '\d+ users'
psql "$DATABASE_URL" -c 'SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 5;'
```

로컬 seed가 운영 데이터를 대표하지 못하면 버그가 숨는다.
특정 legacy row, null 값, 중복 이메일 같은 실제 데이터 패턴을 fixture로 가져와야 한다.

---

## 9. Feature flag 차이

```bash
curl -sS "$FLAG_URL/api/flags?userId=debug-user" \
    -H "authorization: Bearer $TOKEN" \
    | jq -S . > /tmp/flags-debug-user.json
```

flag는 환경뿐 아니라 사용자, tenant, percentage rollout에 따라 다르다.
"스테이징에서는 켜짐, 운영에서는 일부 사용자만 켜짐" 같은 조합을 확인한다.

---

## 10. 컨테이너로 환경 고정

```bash
docker build -t app-debug .
docker run --rm \
    --env-file .env.debug \
    -p 3000:3000 \
    app-debug
```

컨테이너는 runtime과 OS 차이를 줄인다.
하지만 외부 DB, DNS, credentials 차이는 여전히 남는다.

---

## 11. 환경 비교 표

```markdown
| 항목 | 로컬 | 스테이징 | 운영 | 영향 |
|------|------|----------|------|------|
| Node | 20.11 | 20.11 | 20.10 | 확인 필요 |
| TZ | Asia/Seoul | UTC | UTC | 날짜 계산 영향 |
| FEATURE_NEW_PRICE | false | true | 10% | 실패 조건 |
| DB schema | 102 | 103 | 103 | 로컬 migration 누락 |
| Redis mode | standalone | cluster | cluster | key slot 영향 |
```

---

## 12. 완료 기준

- [ ] 실패 환경과 정상 환경의 차이를 표로 정리했다.
- [ ] 동작에 영향을 주는 차이를 검증했다.
- [ ] dependency와 runtime 버전을 확인했다.
- [ ] timezone, locale, OS 차이를 확인했다.
- [ ] 재현 환경을 고정하거나 fixture로 보존했다.
