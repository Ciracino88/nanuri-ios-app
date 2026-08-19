# NanuriAdmin

교회 청년부 회계용 **관리자 1인 전용** iOS 앱 + 청구 접수 워커.

사람이 손으로 넣어야 하는 설정과 남은 할 일은 **`SETUP.md`** 에 있다.
새 세션은 거기부터 볼 것.
증상을 만났다면 **`TROUBLESHOOTING.md`** 를 먼저 본다 — 전에 겪은 것이면 원인과
왜 그렇게 고쳤는지가 거기 있다. **보수 작업을 하면 거기에 남긴다** —
증상 · 원인 · 해결 · 재발 방지 네 가지로, 새 항목은 맨 위에.
화면을 만들거나 고치기 전에는 **`DESIGN.md`** 를 본다. 값은 전부
`Components/DesignSystem.swift` 의 `DS` 에 있고, **화면 코드에 숫자를 직접 적지 않는다.**

## 구성

| 위치 | 내용 |
| --- | --- |
| `NanuriAdmin/` | SwiftUI 앱 (iOS). Xcode 16 파일시스템 동기화 그룹 — **새 .swift 파일은 폴더에 넣으면 자동 인식**, pbxproj 수정 불필요 |
| `worker/` | Cloudflare Worker `nanuri-form`. 공개 청구 폼 + Supabase 저장 + APNs 푸시 |
| `supabase/migrations/` | DB 스키마. 최신 것이 진실이고 앞의 것은 이력 |

원격 이미지는 전부 **`RemoteImage`** 로 그린다 (`Components/RemoteImage.swift`,
Kingfisher). `AsyncImage` 도 `KFImage` 도 직접 쓰지 않는다 — 전자는 캐시도 다운샘플링도
없고, 후자는 `scaleFactor` 를 빠뜨리기 쉽다 (`TROUBLESHOOTING.md`).

앱 탭은 **청구서 / 재정 / 계좌부 / 프로필** 네 개다 (`App/ContentView.swift`).
모든 탭은 `AdminHeaderView` 를 쓰고 내비게이션 바는 없다. 헤더 규칙은 `DESIGN.md` 1번.

`PayeeViewModel` 은 **`ContentView` 가 하나만 만들어** 청구서 탭과 계좌부 탭에
넘긴다. 탭마다 따로 만들면 한쪽에서 등록한 계좌가 다른 쪽에 안 보인다.

## 배포된 것들

| | 주소 / 이름 |
| --- | --- |
| 청구 폼 (공개) | `https://nanuri-form.nanuri.workers.dev` |
| 영수증 R2 워커 | 워커 이름 `nanuri-bill` |
| Supabase | `ciszaukmnglepvqpulya` |

계정 서브도메인은 `nanuri.workers.dev` 다. 이걸 바꾸면 계정의 **모든** 워커 주소가
같이 바뀌고, 앱이 하드코딩한 R2 주소(`Components/ReceiptStorage.swift`)도 고쳐야
한다. 안 고치면 영수증 업로드·삭제가 전부 깨진다.
(저장된 이미지 URL은 `pub-*.r2.dev` 도메인이라 영향 없다)

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
- 같은 사람의 대기중 청구서는 **묶어서 한 번에** 보낸다. 청구서 탭 헤더 왼쪽의
  선택 모드에서 고르면 금액을 합쳐 토스를 한 번만 연다.
  토스 딥링크(`supertoss://send`)가 수취인 한 명·금액 하나라 **사람이 다르면 못 묶는다.**
  승인은 `updateStatus(billIds:)` 로 한 요청에 처리한다 — 나눠 보내면 중간에 끊길 때
  일부만 완료로 남아 나머지가 다시 청구된 것처럼 보인다.
- 실시간 구독은 **`BillViewModel` 이 갖는다.** 화면의 `.task` 에서 돌리면 탭을 옮길 때
  취소되는데, SDK 는 같은 토픽 채널을 캐시해 두고 **이미 구독된 채널에는 콜백을 못
  붙인다.** 그래서 돌아와 다시 구독하면 조용히 죽는다. 되돌리지 말 것.
- `bills` 에 INSERT 정책은 **일부러 없다.** 삽입은 워커의 `service_role` 만 가능하다.
  검증(금액 상한·영수증 필수)을 워커 한 곳에서만 하기 위해서다.

### 영수증은 제출 전에 미리 올라간다

폼은 사진을 고르는 즉시 브라우저에서 축소하고(긴 변 1600px, JPEG 0.8, 4MB→300KB)
`/bill/receipt` 로 미리 올린다. 제출할 때는 받아둔 URL만 넘기므로 버튼을 누른 뒤
기다리는 시간이 거의 없다. 실패하면 축소본을 그대로 붙여 예전 경로를 탄다.

URL은 클라이언트를 거쳐 오므로 그대로 믿으면 안 된다. 워커가 HMAC 서명(`token`)을
같이 주고 제출·폐기 때 검증한다. 접수까지 가지 않은 사진은
`/bill/receipt/discard` 로 지운다 (사진 교체 시 · `pagehide` 시).
자세한 건 `worker/README.md`.

### 영수증 업로드는 서비스 바인딩으로

워커 → R2 워커 호출은 반드시 `env.RECEIPT_WORKER.fetch()` 를 쓴다.
공개 URL로 `fetch` 하면 **요청이 자기 자신으로 되돌아와 404가 난다**
(두 워커가 같은 workers.dev 서브도메인이라서). 실제로 모든 제출이 이걸로 실패했었다.
서비스 바인딩은 DNS도 공용 인터넷도 안 타므로 서브도메인 변경에도 안전하다.

## 반드시 같이 고쳐야 하는 짝

한쪽만 바꾸면 조용히 깨지는 것들이다.

- **이름 정규화** — DB `payees_name_normalized_idx` (`lower(regexp_replace(name,'\s','','g'))`)
  ↔ 앱 `String.normalizedName`. 저장 전 공백 통일은 워커의 `submitterName` 처리
  ↔ 앱 `String.whitespaceNormalized`. 넷이 한 세트다.
  (PG의 `\s`는 U+00A0을 공백으로 안 본다. 그래서 저장 전에 통일한다.)
- **은행 목록** — `Features/Profile/Profile.swift`의 `koreanBanks`.
  토스 송금 딥링크 `supertoss://send?bank=...` 가 이 문자열을 그대로 쓴다.
- **R2 워커 주소** — `Components/ReceiptStorage.swift` ↔ 계정 서브도메인.
- **`import Combine`** — `@Published`/`@StateObject`/`ObservableObject` 쓰는 파일엔 항상 넣는다.

## 인증 / 세션

관리자 1인 전용이라 **세션을 일부러 만료시키지 않는다**.

- 화이트리스트는 DB의 `public.admins` + `is_admin()`. anon key는 앱에 노출돼 있고
  Google provider는 아무 구글 계정이나 로그인시키므로, `authenticated` 만으로는
  보호가 안 된다. **모든 RLS 정책은 `is_admin()` 기준이어야 한다.**
- `AuthViewModel.checkSession()` 은 네트워크를 타지 않는 `auth.currentSession`(키체인)
  으로만 판단한다. `auth.session` 은 갱신 실패 시 throw 하므로, 그걸로 판단하면
  네트워크가 잠깐 없을 때 멀쩡한 세션이 있는데도 로그아웃된다. **되돌리지 말 것.**
- 로그인 화면으로 보내는 건 두 경우뿐 — 저장된 세션이 아예 없을 때, SDK가
  `signedOut`/`userDeleted` 를 쏠 때.
- 서버 쪽 Supabase Auth 설정의 세션 타임박스·비활성 만료가 켜져 있으면
  클라이언트 코드와 무관하게 끊긴다. 세션이 계속 풀리면 대시보드를 먼저 본다.

## DB

새 테이블을 `public` 에 만들면 **반드시 `enable row level security` 를 같이 쓴다.**
anon 에 기본 권한이 열려 있어서(Supabase 기본값), RLS 없는 테이블은 앱 바이너리에
들어 있는 anon key 만으로 읽힌다.

`drop schema public cascade` 는 Supabase가 걸어둔 테이블 권한과
`ALTER DEFAULT PRIVILEGES` 까지 지운다. 그러면 앱도 워커도 `42501 permission denied`
를 받는다. **권한 검사는 RLS보다 먼저다** — 정책이 맞아도 소용없다.
복구는 `20260815130000_restore_public_grants.sql` 참고.

`supabase db push --linked` 는 그냥 실행하면 CLI가 임시 로그인 롤을 만들려다
권한 오류로 실패한다. `SUPABASE_DB_PASSWORD` 를 넘겨 직접 접속해야 한다 (SETUP.md 1번).
비밀번호는 사용자가 직접 입력하게 한다.

## 빌드 / 검증

`xcode-select` 가 CommandLineTools 를 가리키고 있어 `xcodebuild` 가 그냥은 안 된다:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project NanuriAdmin.xcodeproj -scheme NanuriAdmin -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

`wrangler` 는 전역 설치돼 있지 않다. `npx wrangler ...` 로 쓴다.
배포 전 `npx wrangler deploy --dry-run` 으로 설정만 검증할 수 있다.

마이그레이션 SQL 은 던져버릴 postgres 컨테이너에 `auth.users`·`storage`·
`supabase_realtime`·롤을 스텁으로 만들어 두고 적용해 보면 실제로 검증된다.
RLS가 실제로 막는지는 `set role anon;` 으로 직접 찔러보면 된다.

원격 스키마 형태는 anon key로 REST probe 하면 인증 없이 확인된다 —
없는 테이블은 `PGRST205`, 없는 컬럼은 `42703`, 권한 없으면 `42501`.

## 지금 상태 / 남은 일

- 스키마 전환·계좌부·공개 폼은 **끝났고 실제로 동작 확인까지 됐다.**
- 푸시도 **끝났다.** 2026-08-15 실기기 수신까지 확인했다 (`SETUP.md`).
  - 워커는 `device_tokens.environment` 로 APNs 호스트를 고르고, 앱은 `#if DEBUG`
    로 그 값을 정한다. **이 둘이 한 세트다.** Release 구성을 development 프로파일로
    기기에 올리면 `BadDeviceToken` 이 나고 화면에는 아무 것도 안 뜬다.
- 헤더 통일 · 프로필 탭 · 알림함은 2026-08-16 에 넣었고 **빌드만 확인했다.**
  아직 화면으로 못 봤다 (`DESIGN.md` 맨 아래 5번).
- **다음 작업은 계속 디자인 개선이다.** 무엇을 손볼지는 `DESIGN.md` 맨 아래에 있다.

### 알림함은 기기에만 있다

헤더 종 버튼이 여는 목록(`Features/Notification/`)은 **DB 를 안 본다.** 이 기기가
실제로 받은 푸시가 전부다 — 앱이 켜져 있을 때 온 것(`PushAppDelegate`)과 꺼져
있는 동안 와서 알림 센터에 남아 있는 것(`syncFromNotificationCenter`)을 합쳐
`UserDefaults` 에 100개까지 쌓는다.
사용자가 알림 센터에서 지운 알림은 못 줍고, 기기를 바꾸면 비어 있다.
기록이 남아야 한다면 그건 알림 테이블이 필요한 별개의 일이다.

## 주의

- 진짜 비밀은 둘뿐이다 — `SUPABASE_SERVICE_ROLE_KEY`(RLS 우회), `APNS_P8`(푸시 서명 개인키).
  `APNS_TEAM_ID`·`APNS_KEY_ID` 는 식별자라 `wrangler.toml` 에 그냥 적는다.
- 청구 폼은 **공개 URL** 이고 **요청 횟수 제한이 없다.** `[[ratelimits]]` 를 걸어뒀지만
  이 계정에서는 카운팅이 안 된다 (limit=1/10s 로 낮춰도 전부 통과). 실제 방어는
  영수증 필수/10MB/`image/*` + 금액 상한 1,000만 원뿐이다. 자세한 건 `worker/README.md`.
- 이름 사칭은 기술로 막지 않는다. 관리자가 승인 전에 당사자에게 직접 확인하는 것을
  전제로 한 설계다. (사용자 결정)
- 커밋 메시지는 제목·본문 모두 한국어로 쓴다.
