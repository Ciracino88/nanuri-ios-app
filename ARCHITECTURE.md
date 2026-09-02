# 구조와 불변식

**코드를 고치기 전에 보는 문서다.** 여기 있는 건 "이렇게 돼 있다"가 아니라
**"이렇게 해야 하고, 안 그러면 이렇게 깨진다"** 이다.

프로젝트가 무엇인지는 [README.md](README.md), 설정값은 [SETUP.md](SETUP.md),
화면 규칙은 [DESIGN.md](DESIGN.md), 겪은 증상은
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) 에 있다.

---

## 구성

| 위치 | 내용 |
| --- | --- |
| `NanuriAdmin/` | SwiftUI 앱 (iOS). Xcode 16 파일시스템 동기화 그룹 — **새 `.swift` 는 폴더에 넣으면 자동 인식**, `project.pbxproj` 수정 불필요 |
| `worker/` | Cloudflare Worker `nanuri-form`. 공개 청구 폼 + Supabase 저장 + APNs 푸시 |
| `supabase/migrations/` | DB 스키마. 최신 것이 진실이고 앞의 것은 이력 |

### 배포된 것

| | 주소 / 이름 |
| --- | --- |
| 청구 폼 (공개) | `https://nanuri-form.nanuri.workers.dev` |
| 영수증 R2 버킷 | `nanuri-bills` (공개 도메인 `pub-1ff72bbd…r2.dev`) |
| Supabase | `ciszaukmnglepvqpulya` |

계정 서브도메인은 `nanuri.workers.dev` 다. 이걸 바꾸면 계정의 **모든** 워커 주소가
같이 바뀌고, 앱이 하드코딩한 워커 주소(`Components/ReceiptStorage.swift`)도 고쳐야
한다. 안 고치면 영수증 업로드·삭제가 전부 깨진다.
(이미 저장된 이미지 URL 은 `pub-*.r2.dev` 도메인이라 영향 없다)

---

## 데이터 흐름

```
청구자 → 공개 웹 폼(worker) → bills INSERT (service_role) → APNs → 앱
                                                              ↓
                         앱: bills.submitter_name 으로 payees 대조 → 계좌 → 토스 송금
```

- 청구 폼이 받는 값은 **이름·항목·금액·영수증** 네 가지뿐이다. 계좌는 받지 않는다.
- 계좌는 관리자가 앱의 **계좌부 탭(`payees`)** 에 이름↔계좌로 등록해 둔다.
  계좌부에 없는 이름이면 청구서 목록에 "계좌 미등록"으로 뜨고, 누르면 그 이름이
  채워진 등록 시트가 바로 열린다 (목록을 거치지 않는다).

### 묶어 보내기는 같은 사람만 된다

같은 사람의 대기중 청구서는 묶어서 한 번에 보낸다. 청구서 탭 헤더 왼쪽의 선택
모드에서 고르면 금액을 합쳐 토스를 한 번만 연다.

**토스 딥링크(`supertoss://send`)가 수취인 한 명·금액 하나라 사람이 다르면 못 묶는다.**
승인은 `updateStatus(billIds:)` 로 **한 요청에** 처리한다 — 나눠 보내면 중간에
끊길 때 일부만 완료로 남아 나머지가 다시 청구된 것처럼 보인다.

딥링크는 `Features/Bill/TossDeepLink.swift` 에 있다. **URL 을 만드는 일과 여는 일이
나뉘어 있다** — 만드는 쪽은 상태도 UIKit 의존도 없는 순수 함수라 단위 테스트로
검증하고, `UIApplication` 은 여는 쪽만 안다. 뷰모델은 URL 을 조립하지 않는다.

### 영수증은 제출 전에 미리 올라간다

폼은 사진을 고르는 즉시 브라우저에서 축소하고(긴 변 1600px, JPEG 0.8, 4MB→300KB)
`/bill/receipt` 로 미리 올린다. 제출할 때는 받아둔 URL 만 넘기므로 버튼을 누른 뒤
기다리는 시간이 거의 없다. 실패하면 축소본을 그대로 붙여 예전 경로를 탄다.

URL 은 클라이언트를 거쳐 오므로 그대로 믿으면 안 된다. 워커가 HMAC 서명(`token`)을
같이 주고 제출·폐기 때 검증한다. 접수까지 가지 않은 사진은
`/bill/receipt/discard` 로 지운다 (사진 교체 시 · `pagehide` 시).
자세한 건 [worker/README.md](worker/README.md).

### R2 는 워커에 직접 붙어 있다

영수증 버킷은 `env.RECEIPT_BUCKET` 바인딩으로 이 워커에 직접 붙는다
(`worker/src/receipts.js`). **HTTP 로 가지 않는다.**

원래는 `nanuri-bill` 이라는 별도 워커가 버킷을 들고 있었고 여기서는 서비스
바인딩(`env.RECEIPT_WORKER.fetch()`)으로 넘겼다. 그 워커는 대시보드에서 만든 것이라
**소스가 어디에도 없어서** 고칠 수도 되돌릴 수도 없었다. 버킷을 여기 붙이고 코드를
가져오면서 워커가 하나 줄었다.

**그 시절의 교훈은 아직 유효하다** — 다른 워커를 부를 일이 생기면 공개 URL 로
`fetch` 하지 말 것. 같은 workers.dev 서브도메인이면 **요청이 자기 자신으로 되돌아와
404 가 난다.** 실제로 모든 제출이 이걸로 실패했었다.

### 앱 라우트는 admins 화이트리스트로 막는다

앱이 부르는 `/receipt/upload` · `/receipt/delete` 는 **관리자만 부를 수 있다.**
앱이 Supabase 세션의 access token 을 `Authorization: Bearer` 로 넘기고, 워커의
`requireAdmin()` 이 ① Supabase 에 물어 토큰 주인을 확인하고 ② 그 이메일이
`admins` 에 있는지 본다. 없으면 401/403 이다.

**`authenticated` 로는 안 된다.** Google provider 는 아무 구글 계정이나
로그인시키므로 "로그인했다" 는 아무것도 보장하지 않는다. RLS 가 `is_admin()` 을
쓰는 것과 **같은 판단을 같은 표로** 해야 한다.

토큰은 워커가 직접 열어보지 않는다. JWT 서명을 손으로 검증하려면 Supabase 서명 키를
워커가 들고 있어야 하는데 그건 비밀이 하나 더 느는 일이다. Supabase 에 물으면
만료·폐기까지 한 번에 판정된다. 왕복이 한 번 늘지만 영수증 업로드·삭제는 잦지 않다.

옛 `nanuri-bill` 워커에는 이 검사가 없었고, 코드를 옮겨 올 때 그 상태로 한 번
배포됐다가 곧바로 막았다.

---

## 반드시 같이 고쳐야 하는 짝

**한쪽만 바꾸면 조용히 깨지는 것들이다.** 이 목록이 이 문서의 핵심이다.

| 짝 | 위치 |
| --- | --- |
| **이름 정규화** | DB `payees_name_normalized_idx` (`lower(regexp_replace(name,'\s','','g'))`) ↔ 앱 `String.normalizedName` |
| **저장 전 공백 통일** | 워커의 `submitterName` 처리 ↔ 앱 `String.whitespaceNormalized` |
| **은행 목록** | `Features/Profile/Profile.swift` 의 `koreanBanks` ↔ `TossDeepLink` 가 이 문자열을 딥링크의 `bank` 값으로 그대로 넘긴다 |
| **워커 주소** | `Components/ReceiptStorage.swift` ↔ 계정 서브도메인 |
| **R2 공개 도메인** | `worker/wrangler.toml` 의 `R2_PUBLIC_URL` ↔ 이미 저장된 영수증 URL |
| **영수증 라우트 인증** | 워커 `requireAdmin()` ↔ 앱 `ReceiptStorage.accessToken()` |
| **APNs 환경** | 워커의 `device_tokens.environment` ↔ 앱의 `#if DEBUG` |
| **통장 이름** | DB `finance_accounts.name` (`'농협'`·`'모임'`) ↔ 앱 `account(named:)` 의 문자열 |
| **중복 방지 제약** | DB `unique (ledger_id, datetime, amount)` ↔ 앱 `saveTransactions` 의 `upsert`/`insert` |

맨 앞의 둘은 **한 세트**다. PG 의 `\s` 는 U+00A0 을 공백으로 안 보기 때문에
저장 전에 미리 통일해야 인덱스와 앱의 판단이 일치한다.

`R2_PUBLIC_URL` 은 삭제할 때 URL 앞부분을 떼어 키를 얻는 데 쓴다. 바꾸면 **새로
올리는 건 되는데 옛 영수증만 안 지워진다** — 반쪽만 깨져서 알아채기 어렵다.

APNs 환경이 어긋나면 `BadDeviceToken` 이 나고 **화면에는 아무것도 안 뜬다.**
Release 구성을 development 프로파일로 기기에 올릴 때 그렇게 된다.

---

## 화면 규칙 (요약)

전문은 [DESIGN.md](DESIGN.md) 에 있다. 여기서는 코드에 직접 걸리는 것만.

- 값은 두 겹이다 — `Components/DesignSystem.swift` 의 `DS`(뜻이 붙은 시맨틱 층)와
  `Components/DesignTokens.swift` 의 `Ramp`(원시 팔레트).
  **화면은 시맨틱 층만 쓴다. 화면 코드에 숫자를 직접 적지 않는다.**
- 앱 탭은 **청구서 / 재정 / 계좌부 / 프로필** 네 개다 (`App/ContentView.swift`).
  모든 탭은 `AdminHeaderView` 를 쓰고 내비게이션 바는 없다.
- 원격 이미지는 전부 **`RemoteImage`** 로 그린다 (`Components/RemoteImage.swift`).
  `AsyncImage` 도 `KFImage` 도 직접 쓰지 않는다 — 전자는 캐시도 다운샘플링도 없고,
  후자는 `scaleFactor` 를 빠뜨리기 쉽다.

시각 언어의 출처는 [TOSS.md](TOSS.md) 다. 값의 **근거**가 필요하면 거기를 보고,
이 앱에서 그걸 **어떻게 쓰기로 했는지**는 [DESIGN.md](DESIGN.md) 에 있다.

---

## 통장은 둘, 장부는 하나

- **교회법인 농협통장** — 총액을 보관한다. **헌금이 여기로 들어온다** (모임통장은
  헌금 수령처로 승인나지 않았다).
- **토스 모임통장** — 청구를 실시간으로 처리한다. 매달 농협에서 예산을 넘겨 두고
  지출은 여기서 난다. 연합 행사용 통장이 곧 이 통장이라 후원금도 여기로 온다.

**두 통장의 거래내역을 둘 다 보고 하나의 장부에 적는다.** 통장이 둘인데 장부가
하나라는 게 이 구조의 전부다.

월말 결산 때 모임통장 잔액을 농협으로 돌려보내 **매달 0으로 떨어진다.**
`예산 수령 + 후원금 = 지출 + 잔액 반환` 이 한 줄만 빠져도 안 맞아서, 이게 곧
**검산**이다. 저장된 잔액 없이도 도는 검산이라 아래 "잔액은 유도한다" 를 떠받친다.

### 내부 이체는 한 줄이고, 그 줄이 양쪽 통장을 안다

농협에서 모임으로 돈을 옮기는 건 **한 사건인데 통장 둘에 걸친다.**
`finance_transactions.counter_account_id` 가 상대 통장을 들고 있다.

| | `account_id` | `amount` | `counter_account_id` |
| --- | --- | --- | --- |
| 헌금 입금 | 농협 | +500,000 | — |
| 예산 수령 | 농협 | −4,000,000 | 모임 |
| 청구 지출 | 모임 | −85,000 | — |
| 잔액 반환 | 모임 | −312,000 | 농협 |

**비어 있으면 실제 수입·지출, 차 있으면 내부 이체다.** 두 줄(농협 출금 + 모임 입금)로
적지 않는 이유는 그 둘이 같은 사건이라는 걸 따로 짝지어야 하고 **짝이 깨지면 조용히
틀어지기** 때문이다.

이 한 칸이 세 가지를 한다.

1. **통장별 잔액 유도** — `account_id` 쪽은 부호 그대로, `counter_account_id` 쪽은
   **부호를 뒤집어** 더한다 (`FinanceViewModel.balance(of:)`).
   총 재정은 상쇄돼서 저절로 맞는다.
2. **합계·보고서·그래프에서 자동 제외** — 안 빼면 그 달이 부풀어 보인다.
   2026-08 이 실제로 그랬다: 장부상 지출 4,974,200 중 4,000,000 이 내부 이체라
   진짜 지출(974,200)의 **5.1배**로 보였다.
3. `예산 수령`·`잔액 반환` 은 **형태에서 파생되는 이름**이라 사람이 안 고른다.

**뷰모델에서 `filtered` 와 `filteredExternal` 을 구별한다.** 목록은 `filtered`(전부)
— 400만원을 옮긴 사실이 화면에서 사라지면 그게 더 이상하다. 합계·보고서·그래프는
전부 `filteredExternal`(내부 이체 제외)이다. **새 집계를 추가할 때 어느 쪽인지
반드시 정해야 한다.**

## 잔액은 저장하지 않고 유도한다

`finance_transactions.balance` 는 **없앴다** (2026-09-02). 통장 단위 잔액이라
**두 통장을 한 장부에 적는 순간 어느 통장의 잔액도 아니게 됐다** — 농협 거래 다음
줄에 모임 거래가 오면 그 줄의 잔액은 아무것도 아니다.

지금은 `finance_accounts.opening_balance` 에서 출발해 누적한다.

```
통장 잔액 = 개시잔액 + Σ{그 통장을 지나간 amount}
전월이월  = Σ개시잔액 + Σ{그 달 이전의 실제 수입·지출}   ← 내부 이체는 빼고
```

**저장을 지켜도 검증은 못 지킨다.** 수기 입력에서 사람이 넣는 잔액은 은행의 주장이
아니라 사람의 계산이라, 거래를 빠뜨린 사람은 잔액도 그에 맞게 적어 **틀린 계산끼리
맞아떨어진다.** 검증력은 "저장하느냐"가 아니라 "은행이 말한 숫자냐"에서 나온다.
그 자리는 위의 **월말 0원 검산**과, 나중에 붙일 **통장 대조**가 맡는다.

기존 273건은 백필로 전부 농협이 됐다. 근거 둘이 독립적이다 — ① 내부 이체 분류가
하나도 없었다 ② `헌금` 이 80건 있다(헌금은 모임통장으로 못 받으므로 농협 기준 장부다).
마이그레이션 적용 전에 트랜잭션으로 돌려 **273건의 유도 잔액이 옛 `balance` 와 한 원도
안 어긋나는 것**을 확인했다.

## 장부를 고르는 화면이 없다

장부가 하나뿐이라, 재정 탭은 **열자마자 그 장부를 연다** —
`FinanceViewModel.start()` 가 목록을 받아 바로 선택한다.

예전에는 재정 탭에 들어올 때마다 장부를 골라야 했다. `currentLedger` 를 아무 데도
저장하지 않아서 앱을 껐다 켜면 `nil` 이 되고, 하나뿐인 장부를 매번 손으로 골랐다.

- **게이트 화면(`FinanceLedgerGateView`)은 장부가 0개일 때만 나온다.** 사실상 최초 1회다.
  목록도 지우기도 없고 첫 장부를 만드는 것만 한다.
- **`LedgerSwitcherView` 는 삭제했다.** 헤더 왼쪽의 장부 버튼도 없다.
- **`deleteLedger` 는 없다.** 하나뿐인 장부가 전체 회계라 앱에서 지울 수 있으면
  위험하기만 하다. 정말 지워야 하면 Supabase 대시보드에서 한다.

`start()` 는 **이미 열어 둔 장부가 있으면 아무 일도 안 한다.** 탭을 오갈 때마다
다시 고르면 `selectLedger` 가 달 위치를 다시 잡아서 보고 있던 달이 처음으로 돌아간다.

**`ledger_id` 는 그대로 뒀다.** 장부라는 **개념**은 DB 에 남고 **고르는 화면**만 없앤
것이다. `finance_accounts` 도 장부에 매달려 있어서 뺄 자리가 없다.

`unique (ledger_id, datetime, amount)` 는 **뺐다** (2026-09-02). 원래 주석이
"앱이 PDF 재파싱 시 이 조합으로 upsert 한다" 였는데, 그 경로는 **한 번도 쓰인 적이
없다** — 거래 273건이 전부 수기 이관분이고 PDF 로 들어온 건 0건이었다. 반면 수기
입력에서는 사람이 시각을 고르지 않아 **같은 날 같은 금액 거래 둘**(8월 모임통장의
볼링장 결제 같은)이 서로를 막았다. `saveTransactions` 도 `upsert` 에서 `insert` 로
같이 바꿨다 — **한쪽만 되돌리면 런타임에 깨진다.**

## 장부는 전부 월별이다

`finance_ledgers.type` 이 `monthly` | `event` 두 가지였고 화면 골격이 그걸로 갈렸다 —
행사 결산은 달 개념이 없어서 날짜 축도 지난달 비교도 안 그렸다.
**행사 결산을 쓰지 않기로 해서 `event` 를 걷어냈다** (2026-08-25).

- `FinanceReportMode` 열거형이 사라졌다. `Ledger.mode` 도 없다.
- `filtered`·`previousMonthWithdrawal`·`daysInCurrentMonth`·`weeksInCurrentMonth`
  에 있던 `guard ... != .event` 가 전부 빠졌다. 이제 늘 달 단위로 자른다.
- 보고서는 `buildMonthlyHTML` 하나다. `makeReportHTML` 에 `mode` 를 안 넘긴다.
- 새 장부 시트에서 유형 고르는 자리가 없어졌다. 이름만 받는다.

**DB 의 `check (type in ('monthly','event'))` 는 그대로 두었다.** 제약을 좁히는
마이그레이션은 얻는 게 없고, 혹시 남아 있는 옛 행이 있으면 그것만 깨진다.
앱은 늘 `Ledger.monthlyType` 을 넣는다.

---

## 로그

**`print` 를 쓰지 않는다.** `Components/Log.swift` 의 카테고리별 `Logger` 를 쓴다.

이유는 둘이다. `print` 는 stdout 으로만 나가서 Console.app 이나 `log stream` 에서
레벨·카테고리로 걸러 볼 수 없고 릴리스 빌드에도 그대로 남는다. 그리고 **이 앱은
로그에 사람 이름과 계좌번호가 흐른다** — `Logger` 는 문자열 보간을 기본으로
가려서(`<private>`) 남기지만 `print` 는 전부 그대로 찍힌다.

그래서 **개인정보가 섞일 수 있는 값은 보간에 그대로 넣는다** (가려지는 게 기본값).
늘 보여야 하는 값에만 `privacy: .public` 을 붙인다.

`Logger` 의 보간 문법은 **부르는 파일마다 `import OSLog`** 가 필요하다.
`Log` 를 정의한 파일에만 넣어서는 안 된다.

---

## 상태 소유

### `PayeeViewModel` 은 하나뿐이다

**`ContentView` 가 하나만 만들어** 청구서 탭과 계좌부 탭에 넘긴다.
탭마다 따로 만들면 한쪽에서 등록한 계좌가 다른 쪽에 안 보인다.

### 실시간 구독은 `BillViewModel` 이 갖는다

화면의 `.task` 에서 돌리면 탭을 옮길 때 취소되는데, SDK 는 같은 토픽 채널을
캐시해 두고 **이미 구독된 채널에는 콜백을 못 붙인다.** 그래서 돌아와 다시
구독하면 조용히 죽는다. **되돌리지 말 것.** (경위는 TROUBLESHOOTING.md)

### 알림함은 기기에만 있다

헤더 종 버튼이 여는 목록(`Features/Notification/`)은 **DB 를 안 본다.** 이 기기가
실제로 받은 푸시가 전부다 — 앱이 켜져 있을 때 온 것(`PushAppDelegate`)과 꺼져
있는 동안 와서 알림 센터에 남아 있는 것(`syncFromNotificationCenter`)을 합쳐
`UserDefaults` 에 100개까지 쌓는다.

사용자가 알림 센터에서 지운 알림은 못 줍고, 기기를 바꾸면 비어 있다.
기록이 남아야 한다면 그건 알림 테이블이 필요한 별개의 일이다.

---

## 인증 / 세션

관리자 1인 전용이라 **세션을 일부러 만료시키지 않는다.**

- 화이트리스트는 DB 의 `public.admins` + `is_admin()`. anon key 는 앱에 노출돼 있고
  Google provider 는 아무 구글 계정이나 로그인시키므로, `authenticated` 만으로는
  보호가 안 된다. **모든 RLS 정책은 `is_admin()` 기준이어야 한다.**
- `AuthViewModel.checkSession()` 은 네트워크를 타지 않는 `auth.currentSession`(키체인)
  으로만 판단한다. `auth.session` 은 갱신 실패 시 throw 하므로, 그걸로 판단하면
  네트워크가 잠깐 없을 때 멀쩡한 세션이 있는데도 로그아웃된다. **되돌리지 말 것.**
- 로그인 화면으로 보내는 건 두 경우뿐 — 저장된 세션이 아예 없을 때, SDK 가
  `signedOut`/`userDeleted` 를 쏠 때.
- 서버 쪽 Supabase Auth 설정의 세션 타임박스·비활성 만료가 켜져 있으면
  클라이언트 코드와 무관하게 끊긴다. 세션이 계속 풀리면 대시보드를 먼저 본다.

---

## DB

`bills` 에 INSERT 정책은 **일부러 없다.** 삽입은 워커의 `service_role` 만 가능하다.
검증(금액 상한·영수증 필수)을 **워커 한 곳에서만** 하기 위해서다.
정책을 열면 검증이 두 군데가 되고, 두 군데는 언젠가 어긋난다.

새 테이블을 `public` 에 만들면 **반드시 `enable row level security` 를 같이 쓴다.**
anon 에 기본 권한이 열려 있어서(Supabase 기본값), RLS 없는 테이블은 앱 바이너리에
들어 있는 anon key 만으로 읽힌다.

`drop schema public cascade` 는 Supabase 가 걸어둔 테이블 권한과
`ALTER DEFAULT PRIVILEGES` 까지 지운다. 그러면 앱도 워커도 `42501 permission denied`
를 받는다. **권한 검사는 RLS 보다 먼저다** — 정책이 맞아도 소용없다.
복구는 `20260815130000_restore_public_grants.sql` 참고.

---

## 검증하는 법

마이그레이션 SQL 은 던져버릴 postgres 컨테이너에 `auth.users`·`storage`·
`supabase_realtime`·롤을 스텁으로 만들어 두고 적용해 보면 실제로 검증된다.
RLS 가 실제로 막는지는 `set role anon;` 으로 직접 찔러보면 된다.

원격 스키마 형태는 anon key 로 REST probe 하면 인증 없이 확인된다 —
없는 테이블은 `PGRST205`, 없는 컬럼은 `42703`, 권한 없으면 `42501`.

**화면을 눈으로 확인하려면 사람이 필요하다.** 시뮬레이터는 띄울 수 있지만
Google 로그인 벽에서 막힌다. 로그인된 상태를 만들어 주거나 실기기 스크린샷을
받아야 화면을 볼 수 있다. 푸시도 시뮬레이터에서는 확인이 안 된다.

---

## 빌드

`xcode-select` 가 CommandLineTools 를 가리키고 있으면 `xcodebuild` 가 그냥은 안 된다.
앞에 `DEVELOPER_DIR` 을 붙인다. (`xcode-select -p` 로 먼저 확인)

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project NanuriAdmin.xcodeproj -scheme NanuriAdmin -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

워커는 `wrangler` 가 전역 설치돼 있지 않아 `npx` 로 쓴다. 배포 전에 설정만 검증할 수 있다 —
바인딩과 변수가 의도대로 잡혔는지 여기서 보인다.

```bash
cd worker && npx wrangler deploy --dry-run
```

푸시는 시뮬레이터에서 확인이 안 된다. **실기기가 필요하다.**
