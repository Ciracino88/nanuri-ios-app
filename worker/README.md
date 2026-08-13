# 나누리 청구 접수 워커

카카오톡 챗봇으로 들어온 청구를 받아 Supabase에 저장하고, 관리자 앱에 푸시를 보낸다.

```
채팅방 [청구하기]
  → POST /kakao/skill    서명된 폼 링크를 카드로 응답 (유효 30분)
  → GET  /bill/form      카카오톡 인앱 브라우저에서 열리는 청구 폼
  → POST /bill/submit    검증 → 영수증 업로드 → bills INSERT → APNs 푸시
```

영수증 이미지는 직접 다루지 않고 기존 R2 워커(`/upload`)에 위임한다.
앱이 이미 아는 URL 형식을 그대로 유지하기 위해서다.

## 배포

```bash
cd worker
npm install -g wrangler   # 이미 있으면 생략
wrangler login
```

시크릿 등록 (값은 프롬프트에 입력):

```bash
wrangler secret put SUPABASE_SERVICE_ROLE_KEY
wrangler secret put TOKEN_SECRET
wrangler secret put KAKAO_SKILL_SECRET
wrangler secret put APNS_KEY_ID
wrangler secret put APNS_TEAM_ID
wrangler secret put APNS_P8
```

- `SUPABASE_SERVICE_ROLE_KEY` — Supabase 대시보드 > Project Settings > API. **RLS를 우회하는 키다.** 앱이나 저장소에 넣지 말 것.
- `TOKEN_SECRET` — 아무 긴 임의 문자열. `openssl rand -base64 32` 로 만들면 된다.
- `KAKAO_SKILL_SECRET` — 챗봇 블록의 스킬 설정에 같은 값을 넣어둔다.
- `APNS_*` — Apple Developer > Keys 에서 APNs 키(.p8)를 발급하고 얻는 값들. `APNS_P8`은 파일 내용 전체를 `-----BEGIN PRIVATE KEY-----` 줄까지 포함해 붙여넣는다.

배포:

```bash
wrangler deploy
```

배포 후 나온 주소를 `wrangler.toml`의 `PUBLIC_BASE_URL`에 반영하고 한 번 더 배포한다.
(폼 링크를 이 값으로 만들기 때문에 처음 한 번은 두 번 배포해야 한다.)

## 챗봇 관리자센터 설정

1. 스킬 등록 — URL을 `https://<배포주소>/kakao/skill` 로 지정
2. "청구하기" 블록 생성 → 위 스킬 연결
3. 스킬 파라미터에 `secret` = `KAKAO_SKILL_SECRET` 값 추가
   (헤더를 넣을 수 있으면 `x-nanuri-secret` 헤더를 써도 된다)

## 확인

```bash
curl -X POST https://<배포주소>/kakao/skill \
  -H 'content-type: application/json' \
  -H 'x-nanuri-secret: <KAKAO_SKILL_SECRET>' \
  -d '{"userRequest":{"user":{"id":"test-user"}}}'
```

응답의 `webLinkUrl`을 브라우저로 열면 폼이 떠야 한다.

## 알아둘 점

- 토큰은 30분 안에서 재사용할 수 있다. 한 번 받은 링크로 여러 건을 넣을 수 있다는
  뜻인데, 정상 사용(연달아 두 건 청구)과 구분되지 않아 일부러 막지 않았다.
  문제가 되면 제출 시 토큰을 소모 처리하도록 KV를 붙이면 된다.
- 폼의 은행 목록은 앱 `Profile.swift`의 `koreanBanks`와 같아야 한다.
  토스 송금 딥링크가 이 문자열을 그대로 쓰기 때문에 한쪽만 고치면 송금이 깨진다.
