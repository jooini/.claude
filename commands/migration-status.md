# /migration-status - 마이그레이션 상태 확인

T_Member (SQL Server)와 Keycloak 사용자 데이터를 비교하여 마이그레이션 진행률을 확인한다.

## 사용법

- `/migration-status` - 전체 마이그레이션 상태
- `/migration-status detail` - 상세 통계 (이메일, 비밀번호, 소셜 로그인)

## 인자

$ARGUMENTS

## 수행 작업

### 1단계: T_Member 통계 (dev2-backend 컨테이너 경유)

SSH → maxai-b2c-backend 컨테이너에서 SQL Server 쿼리:

DB 접속 정보: 컨테이너 내 `.env`의 `DB_MAX_*` 또는 기본값 `115.68.153.153:1433 / speakingMax_260102`

```sql
-- 회원 상태별 수
SELECT m_secede, COUNT(*) as cnt FROM T_Member GROUP BY m_secede

-- 활성 사용자 수
SELECT COUNT(*) FROM T_Member WHERE m_secede = '0'
```

### 2단계: Keycloak 사용자 수

Identity Hub API로 Keycloak 사용자 수 확인:
```bash
ssh dev2-backend 'docker exec dev-maxai-identity-hub curl -s "http://localhost:8000/api/v1/users/weaversbrain?max=1" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))"'
```

또는 Keycloak Admin API 직접 호출:
```bash
# 사용자 수 카운트
ssh dev2-backend 'docker exec dev-maxai-identity-keycloak /opt/keycloak/bin/kcadm.sh get users/count -r weaversbrain --server http://localhost:8080 --realm master --user admin --password {password}'
```

### 3단계: 마이그레이션 진행률 계산

```
전체 활성 사용자 (T_Member m_secede='0'): X명
Keycloak 사용자: Y명
마이그레이션 완료: Y/X (XX%)
미마이그레이션: X-Y명
```

### 4단계: 상세 통계 (detail 인자)

```sql
-- 비밀번호 형식 분포
SELECT
  SUM(CASE WHEN m_pass IS NULL OR m_pass = '' THEN 1 ELSE 0 END) as no_pass,
  SUM(CASE WHEN LEN(m_pass) = 32 THEN 1 ELSE 0 END) as md5_pass,
  SUM(CASE WHEN LEN(m_pass) <> 32 AND m_pass IS NOT NULL AND m_pass <> '' THEN 1 ELSE 0 END) as other
FROM T_Member WHERE m_secede = '0'

-- 이메일 유효성 분포
SELECT
  SUM(CASE WHEN m_email IS NULL THEN 1 ELSE 0 END) as null_email,
  SUM(CASE WHEN m_email = '@' THEN 1 ELSE 0 END) as at_only,
  SUM(CASE WHEN m_email LIKE '%@%.%' AND m_email <> '@' THEN 1 ELSE 0 END) as valid_email
FROM T_Member WHERE m_secede = '0'

-- 소셜 로그인 연동
SELECT extType, COUNT(*) as cnt
FROM T_Member_ExtToken et
JOIN T_Member m ON m.mIdx = et.mIdx
WHERE m.m_secede = '0' AND et.isUsed = 1
GROUP BY extType

-- 중복 username
SELECT m_id, COUNT(*) as cnt FROM T_Member
WHERE m_secede = '0' GROUP BY m_id HAVING COUNT(*) > 1
```

### 출력 형식

```
=== 마이그레이션 상태 ===

[T_Member]
  활성 (m_secede=0): 12,345명
  탈퇴 (m_secede=1): 2,100명
  휴면 (m_secede=2): 890명

[Keycloak]
  전체 사용자: 1,234명

[진행률]
  ████████░░░░░░░░ 10.0% (1,234 / 12,345)
  미마이그레이션: 11,111명

[상세] (--detail)
  비밀번호: MD5 11,000명 / 없음 1,345명
  이메일: 유효 5,000명 / NULL 6,000명 / '@'만 1,345명
  소셜 연동: NAVER 3,000건 / KAKAO 2,000건 / APPLE 500건
  중복 username: 5건
```
