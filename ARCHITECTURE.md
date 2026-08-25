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
| 영수증 R2 워커 | 워커 이름 `nanuri-bill` |
| Supabase | `ciszaukmnglepvqpulya` |

계정 서브도메인은 `nanuri.workers.dev` 다. 이걸 바꾸면 계정의 **모든** 워커 주소가
같이 바뀌고, 앱이 하드코딩한 R2 주소(`Components/ReceiptStorage.swift`)도 고쳐야
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

### 워커 → R2 는 서비스 바인딩으로

워커에서 R2 워커를 부를 때는 반드시 `env.RECEIPT_WORKER.fetch()` 를 쓴다.
공개 URL 로 `fetch` 하면 **요청이 자기 자신으로 되돌아와 404가 난다**
(두 워커가 같은 workers.dev 서브도메인이라서). 실제로 모든 제출이 이걸로 실패했었다.
서비스 바인딩은 DNS 도 공용 인터넷도 안 타므로 서브도메인 변경에도 안전하다.

---

## 반드시 같이 고쳐야 하는 짝

**한쪽만 바꾸면 조용히 깨지는 것들이다.** 이 목록이 이 문서의 핵심이다.

| 짝 | 위치 |
| --- | --- |
| **이름 정규화** | DB `payees_name_normalized_idx` (`lower(regexp_replace(name,'\s','','g'))`) ↔ 앱 `String.normalizedName` |
| **저장 전 공백 통일** | 워커의 `submitterName` 처리 ↔ 앱 `String.whitespaceNormalized` |
| **은행 목록** | `Features/Profile/Profile.swift` 의 `koreanBanks` ↔ `TossDeepLink` 가 이 문자열을 딥링크의 `bank` 값으로 그대로 넘긴다 |
| **R2 워커 주소** | `Components/ReceiptStorage.swift` ↔ 계정 서브도메인 |
| **APNs 환경** | 워커의 `device_tokens.environment` ↔ 앱의 `#if DEBUG` |

위 넷 중 앞의 둘은 **한 세트**다. PG 의 `\s` 는 U+00A0 을 공백으로 안 보기 때문에
저장 전에 미리 통일해야 인덱스와 앱의 판단이 일치한다.

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

빌드 명령은 [README.md](README.md#빌드) 에 있다.
