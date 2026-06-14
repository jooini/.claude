---
name: from-import-binding-monkeypatch
description: `from X import Y` 로 가져온 심볼은 원본 모듈 monkeypatch 가 무효. 사용자 모듈 자체를 패치해야 적용됨
metadata:
  type: feedback
---

Python 의 `from X import Y` 는 호출자 모듈에 Y 의 **새 바인딩** 을 만든다. 그 후 X.Y 를 monkeypatch 해도 호출자 모듈의 Y 바인딩은 그대로 원본을 가리킨다.

**실측 사례 (identity-hub oauth redirect 테스트):**
```python
# app/api/v1/endpoints/oauth.py
from app.utils.redirect import validate_redirect_uri  # 모듈 바인딩 생성

# tests/integration/test_oauth_redirects.py
from app.utils import redirect as redirect_utils
monkeypatch.setattr(redirect_utils, "validate_redirect_uri", lambda *a, **kw: False)
# → app.utils.redirect.validate_redirect_uri 만 변경됨
# → oauth.py 의 validate_redirect_uri 호출은 여전히 원본 → 테스트 FAIL
```

**해결:**
```python
from app.api.v1.endpoints import oauth as oauth_module
monkeypatch.setattr(oauth_module, "validate_redirect_uri", lambda *a, **kw: False)
# → oauth.py 의 바인딩 자체를 교체 → 핸들러가 mock 호출
```

**Why:** Python import 메커니즘의 기본 동작. 회피하려면 호출자가 `import app.utils.redirect` 후 `app.utils.redirect.validate_redirect_uri(...)` 로 호출해야 하는데, 그건 production 코드 강제 변경이라 부적절.

**How to apply:** monkeypatch.setattr 로 함수 mock 할 때:
1. 호출자 모듈의 import 형식 먼저 확인 (`from X import Y` 인지 `import X` 인지)
2. `from-import` 면 호출자 모듈 자체를 패치 대상으로 지정
3. `import X` 면 원본 모듈 패치도 동작
4. 의심스러우면 양쪽 다 시도해 PASS 하는 쪽 채택

같은 함정이 `unittest.mock.patch("X.Y")` 에서도 적용 — patch path 는 **사용처** 기준이지 정의처 기준이 아니다.
