# 나누리 청구 접수 워커

공개 웹페이지로 들어온 청구를 받아 Supabase에 저장하고, 관리자 앱에 푸시를 보낸다.

```
GET  /  (= /bill)     공개 청구 폼
POST /bill/submit     검증 → 영수증 업로드 → bills INSERT → APNs 푸시
```

폼에서 받는 값은 네 가지다 — **이름, 청구 항목, 금액, 영수증 사진**.
은행·계좌는 받지 않는다. 관리자가 앱의 **계좌부**에 이름↔계좌를 등록해 두면,
들어온 청구서의 이름을 대조해서 송금 계좌를 찾는다.

영수증 이미지는 직접 다루지 않고 기존 R2 워커(`/upload`)에 위임한다.
앱이 이미 아는 URL 형식을 그대로 유지하기 위해서다.

## 공개 URL이라는 점

주소를 아는 사람은 누구나 청구를 넣을 수 있고, 발신자를 식별할 방법이 없다.
현재 실제로 걸려 있는 방어는 이것뿐이다.

- 영수증 필수, 10MB 이하, `image/*` 만
- 금액 상한 1,000만 원, 이름 30자·항목 60자 제한
- 폼에 `noindex`

**요청 횟수 제한은 없다.** `[[ratelimits]]` 바인딩을 걸어뒀지만 2026-08-15 확인 결과
이 계정에서는 카운팅이 되지 않는다 (limit=1/10s 로 낮춰도 전부 통과). 설정은 문서와
일치하고 바인딩도 런타임에 존재하므로 원인은 플랜/계정 쪽으로 추정한다.
자세한 건 `wrangler.toml` 의 `[[ratelimits]]` 주석에 적어뒀다.

즉 한 사람이 R2에 이미지를 계속 밀어넣는 걸 막을 장치가 지금은 없다.
장난 청구는 앱에서 지우면 되지만, 문제가 되면 Turnstile을 붙이거나
접수 경로를 다시 좁히는 게 다음 수순이다.

이름을 사칭한 청구는 애초에 기술로 막지 않는다. 관리자가 승인 전에 당사자에게
직접 확인하는 것을 전제로 한 설계다.

## 배포

wrangler는 전역 설치 없이 `npx` 로 쓴다. (전역 설치돼 있으면 `npx` 를 빼도 된다)

```bash
cd worker
npx wrangler login   # 이미 로그인돼 있으면 생략. npx wrangler whoami 로 확인
```

시크릿 등록 (값은 프롬프트에 입력):

```bash
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_P8
```

- `SUPABASE_SERVICE_ROLE_KEY` — Supabase 대시보드 > Project Settings > API. **RLS를 우회하는 키다.** 앱이나 저장소에 넣지 말 것.
- `APNS_*` — Apple Developer > Keys 에서 APNs 키(.p8)를 발급하고 얻는 값들. `APNS_P8`은 파일 내용 전체를 `-----BEGIN PRIVATE KEY-----` 줄까지 포함해 붙여넣는다.

배포 전에 업로드 없이 설정만 확인해 볼 수 있다:

```bash
npx wrangler deploy --dry-run
```

배포:

```bash
npx wrangler deploy
```

배포 후 나온 주소가 곧 청구 폼 주소다. 이 주소를 청년부에 공유하면 된다.
(예전처럼 링크를 서명해서 만들지 않으므로 두 번 배포할 필요가 없다.)

## 확인

```bash
curl -s https://<배포주소>/ | head -20
```

폼 HTML이 나오면 정상이다. 브라우저로 열어 실제로 한 건 넣어보고,
앱 청구서 목록에 뜨는지 확인한다.

## 알아둘 점

- 이름 대조는 공백·대소문자를 무시한다("홍 길동" = "홍길동").
  DB의 `payees_name_normalized_idx` 와 앱의 `String.normalizedName` 이
  같은 규칙을 쓴다. 한쪽만 고치면 매칭이 어긋난다.
- 계좌부에 없는 이름으로 청구가 들어오면 앱에서 "계좌 미등록"으로 표시되고,
  그 자리에서 계좌를 등록할 수 있다.
