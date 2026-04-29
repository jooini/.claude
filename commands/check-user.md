# /check-user - 사용자 조회 (T_Member + Keycloak)

mIdx 또는 username으로 레거시 DB(T_Member)와 Keycloak 양쪽을 동시에 조회하여 비교한다.
마이그레이션 상태, 소셜 로그인 연동 여부, 비밀번호 형식 등을 한눈에 확인한다.

## 사용법

- `/check-user sm_leonard` - username으로 조회
- `/check-user 1179409` - mIdx로 조회

## 인자

$ARGUMENTS

인자가 숫자면 mIdx, 문자열이면 username으로 판단한다.

## 수행 작업

### 1단계: T_Member 조회 (dev2-backend 컨테이너 경유)

SSH → dev2-backend → maxai-b2c-backend 컨테이너에서 PHP로 SQL Server 쿼리:

```sql
SELECT mIdx, m_id, m_name, m_email, m_mobile, m_pass,
       m_secede, m_dormStatus, m_regdate, m_joinPath, m_snsInfo
FROM T_Member
WHERE m_id = '{username}' OR mIdx = {mIdx}
```

DB 접속 정보:
- Host: 컨테이너 내 `.env`에서 `DB_MAX_*` 읽기
- 또는 기본값: `115.68.153.153:1433 / speakingMax_260102`

### 2단계: T_Member_ExtToken 조회

```sql
SELECT extIdx, extType, extId, extName, isUsed, extConDate
FROM T_Member_ExtToken
WHERE mIdx = {mIdx}
ORDER BY extIdx
```

### 3단계: Keycloak 사용자 조회 (Identity Hub API)

dev2-backend 컨테이너에서 Identity Hub API 호출:

```bash
curl -s http://dev-maxai-identity-hub:8000/api/v1/users/weaversbrain/username/{username}
```

### 4단계: 비교 결과 출력

```
=== 사용자 조회: sm_leonard ===

[T_Member]
  mIdx: 1179409
  m_id: sm_leonard
  m_name: 주인식
  m_email: (NULL)
  m_mobile: 010-xxxx-xxxx
  m_pass: e10adc39... (MD5, 32자)
  m_secede: 0 (활성)
  m_regdate: 2023-01-01

[Keycloak]
  id: abc-def-123
  username: sm_leonard
  firstName: 주인식
  enabled: true
  attributes.mIdx: 1179409
  attributes.phoneNumber: 010-xxxx-xxxx

[소셜 로그인]
  ExtToken: NAVER (extId: 7299532, isUsed: 1)
  Federated Identity: naver (7299532) ✅ 연결됨

[마이그레이션 상태]
  T_Member: ✅ 존재
  Keycloak: ✅ 존재
  mIdx 매핑: ✅ 일치
  비밀번호: MD5 (마이그레이션 후 PBKDF2 재해싱 필요)
```

Keycloak에 없으면 "마이그레이션 필요" 표시.
mIdx가 불일치하면 경고.
