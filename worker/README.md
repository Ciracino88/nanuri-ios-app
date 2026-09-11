# 나누리 청구 접수 워커

공개 웹페이지로 들어온 청구를 받아 Supabase에 저장하고, 관리자 앱에 푸시를 보낸다.

```
GET  /  (= /bill)          공개 청구 폼
POST /bill/receipt         영수증만 먼저 올린다 → { url, token }
POST /bill/receipt/discard 접수까지 가지 않은 영수증을 지운다
POST /bill/submit          검증 → bills INSERT → APNs 푸시

POST /receipt/upload       앱이 영수증을 올린다 → { url }   [관리자 인증]
POST /receipt/delete       앱이 영수증을 지운다              [관리자 인증]
```

`/bill/*` 은 공개 폼이 부르고, `/receipt/*` 은 앱이 부른다.

## 한눈에

```mermaid
flowchart TD
    U([청구자]) -->|GET /| F[공개 청구 폼]

    F -->|"사진 고르면 바로<br/>POST /bill/receipt"| R1{"IP당 상한<br/>분당 20, 시간당 120"}
    R1 -->|초과| E1[429]
    R1 -->|통과| BUCKET[("R2 버킷<br/>nanuri-bills")]

    F -->|"제출<br/>POST /bill/submit"| R2{"IP당 상한<br/>분당 10"}
    R2 -->|초과| E2[429]
    R2 -->|통과| V["검증<br/>금액, 길이, 영수증 서명"]
    V -->|"service_role INSERT"| DB[("Supabase bills")]
    V -->|백그라운드| P[APNs 푸시]
    P --> A([관리자 앱])
    DB -.->|receipt_url| BUCKET

    A -->|"POST /receipt/upload, delete<br/>관리자 인증"| BUCKET

    C{{"cron 매일 03:00 KST"}} --> CL[고아 영수증 정리]
    DB -.->|참조된 URL 목록| CL
    CL -.->|참조 안 된 것만 삭제| BUCKET
```

- **실선은 요청**, 점선은 참조나 정리처럼 요청 밖에서 일어나는 흐름이다.
- 공개 폼(`/bill/*`)은 IP당 상한을 지나야 R2나 DB에 닿는다. 앱(`/receipt/*`)은 관리자 인증으로 막는다.
- 예약 실행이 R2에 남은 고아 영수증을 쓸어내되, **DB가 참조하는 것은 절대 안 지운다.**

폼에서 받는 값은 네 가지다 — **이름, 청구 항목, 금액, 영수증 사진**.
은행·계좌는 받지 않는다. 관리자가 앱의 **계좌부**에 이름↔계좌를 등록해 두면,
들어온 청구서의 이름을 대조해서 송금 계좌를 찾는다.

영수증 이미지는 이 워커가 직접 R2에 넣는다 (`src/receipts.js`, 바인딩
`RECEIPT_BUCKET` → 버킷 `nanuri-bills`). 원래는 `nanuri-bill` 이라는 별도 워커에
서비스 바인딩으로 넘겼는데, 그 워커는 대시보드에서 만든 것이라 **소스가 어디에도
없어서** 고칠 수가 없었다. 버킷을 여기 붙이고 코드를 가져왔다.

저장되는 URL 형식은 그대로다 — `R2_PUBLIC_URL` + `/` + 키. 앱이 이미 들고 있는
옛 URL 도 같은 버킷의 같은 키라서 계속 열리고 지워진다.

## 영수증은 제출 전에 미리 올라간다

제출이 느린 원인은 전부 사진이었다. 폰 사진은 2~5MB인데 그걸 **제출 버튼을 누른
뒤에** 올리기 시작했으니, 회선이 나쁘면 십수 초를 기다려야 했다.

지금은 폼이 두 가지를 한다.

1. 사진을 고르는 즉시 브라우저에서 축소한다 (긴 변 1600px, JPEG 0.8).
   4MB짜리가 300KB 안팎이 된다. HEIC 도 여기서 JPEG 가 된다.
2. 그 축소본을 `/bill/receipt` 로 **미리** 올려둔다. 사용자가 항목·금액을 채우는
   동안 끝난다. 제출할 때는 받아둔 URL만 넘기므로 왕복이 INSERT 하나로 줄어든다.

미리 올렸는데 접수까지 오지 않은 사진은 R2에 남는다. 폼은 사진을 다른 걸로 바꿨을
때와 접수 전에 창을 닫을 때(`pagehide` + `sendBeacon`) `/bill/receipt/discard` 로
지운다. 브라우저가 못 보내고 꺼지는 경우는 못 막아 고아가 남는데, 그건 **예약 실행이
쓸어낸다** (아래 "고아 영수증 정리").

**선행 업로드가 실패해도 접수는 된다.** 그때는 축소본을 그대로 붙여 예전 경로
(`/bill/submit` 이 직접 업로드)로 보낸다. JS가 안 도는 브라우저도 이 경로를 탄다.

### URL을 그대로 믿으면 안 된다

두 라우트 모두 URL을 클라이언트한테서 받는다. 그냥 믿으면 아무 주소나 적어 넣어
관리자 앱이 남의 서버 이미지를 불러오게 만들거나, URL만 알면 남의 영수증을 지울 수
있다. 그래서 `/bill/receipt` 는 URL에 HMAC-SHA256 서명(`token`)을 찍어서 같이 주고,
제출·폐기 때 그 서명을 검증한다. 서명 키는 이 워커에만 있으므로 위조할 수 없다.
폐기는 한 겹 더 본다 — 이미 `bills` 에 쓰인 영수증이면 거절한다.
`token` 은 DB에 저장되지 않고 1시간 뒤 만료된다.

## 공개 URL이라는 점

주소를 아는 사람은 누구나 청구를 넣을 수 있고, 발신자를 식별할 방법이 없다.
현재 실제로 걸려 있는 방어는 이것뿐이다.

- 영수증 필수, 10MB 이하, `image/*` 만 (`/bill/receipt` 도 같은 검사를 한다)
- 금액 상한 1,000만 원, 이름 30자·항목 60자 제한
- 폼에 `noindex`
- **IP당 요청 횟수 제한** — `/bill/receipt` 는 분당 20건에 시간당 120건, `/bill/submit`
  은 분당 10건. 넘으면 429다.

요청 횟수 제한은 KV로 센다 (`RATE_KV`, `src/index.js` 의 `withinRateLimit`). 원래는
네이티브 `[[ratelimits]]` 바인딩을 썼는데 이 계정에서는 카운팅이 안 됐다(limit=1/10s
로 낮춰도 전부 통과 — 플랜/계정 수준 문제로 추정). 상한을 넉넉히 둔 이유는 CGNAT나
공용 와이파이로 **여러 사람이 한 IP로 보일 수 있어서**다. IPv6는 앞 /64로 묶어 센다.
자세한 근거는 `wrangler.toml` 의 `[[kv_namespaces]]` 주석에 있다.

여기에 R2 고아 정리(아래)가 더해져, 한 사람이 이미지를 계속 밀어넣어도 유입이 IP당
시간당 120으로 캡되고 접수까지 안 온 파일은 자동으로 지워진다. 그래도 진짜
브라우저를 돌리는 정교한 공격까지 막으려면 Turnstile을 붙이는 게 다음 수순이다.

이름을 사칭한 청구는 애초에 기술로 막지 않는다. 관리자가 승인 전에 당사자에게
직접 확인하는 것을 전제로 한 설계다.

## 고아 영수증 정리

미리 올렸지만 접수까지 오지 않은 영수증을 예약 실행(`scheduled`, 매일 03:00 KST,
`wrangler.toml` 의 `[triggers]`)이 쓸어낸다.

**참조된 영수증은 절대 안 지운다.** 미리 올린 것과 접수까지 간 진짜 영수증이 같은 키
공간에 살기 때문에, "오래된 것 삭제" 로 일괄 처리하면 장부의 증거까지 지워진다.
그래서 DB가 실제로 쓰는 URL을 다 모아 그 목록에 없는 것만 지운다. 참조는 두
군데다 — `bills.receipt_url`(공개 폼)과 `finance_items.receipt_urls`(앱/재정). 둘 중
하나라도 못 읽으면 **아무것도 안 지운다**(fail-closed). PostgREST 기본 상한(1000행)에
걸려 목록이 반쪽이 되지 않도록 페이지를 끝까지 넘겨 읽는다. 막 올려 아직 저장 전인
파일을 지우지 않도록 6시간 유예를 둔다.

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
- **`/receipt/*` 는 관리자만 부를 수 있다.** 앱이 Supabase access token 을
  `Authorization: Bearer` 로 넘기고, `requireAdmin()` 이 토큰 주인을 확인한 뒤
  `admins` 화이트리스트를 본다. 로그인만으로는 안 된다 — Google provider 는 아무
  구글 계정이나 로그인시키므로 RLS 의 `is_admin()` 과 같은 표를 봐야 한다.
  (공개 폼이 쓰는 `/bill/*` 는 다른 방식이다 — 사람을 알 수 없으므로 URL 에 HMAC
  서명을 찍어 "이 워커가 준 URL 이 맞다" 만 확인한다.)
- **`R2_PUBLIC_URL` 을 바꾸면 반쪽만 깨진다.** 삭제할 때 이 앞부분을 떼어 키를 얻기
  때문에, 새로 올리는 건 되는데 **옛 영수증만 안 지워진다.** 업로드가 되니까 맞게
  붙인 줄 알기 쉽다.
