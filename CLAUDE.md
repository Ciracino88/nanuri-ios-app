# NanuriAdmin

교회 청년부 회계용 **관리자 1인 전용** iOS 앱 + 청구 접수 워커.

## 구성

| 위치 | 내용 |
| --- | --- |
| `NanuriAdmin/` | SwiftUI 앱 (iOS). Xcode 16 파일시스템 동기화 그룹 — **새 .swift 파일은 폴더에 넣으면 자동 인식**, pbxproj 수정 불필요 |
| `worker/` | Cloudflare Worker. 공개 청구 폼 + Supabase 저장 + APNs 푸시 |
| `supabase/migrations/` | DB 스키마. 최신 것이 진실이고 앞의 것은 이력 |

앱 탭은 **청구서 / 재정 / 안내** 세 개다 (`App/ContentView.swift`).

## 데이터 흐름

```
청구자 → 공개 웹 폼(worker) → bills INSERT (service_role) → APNs → 앱
                                                              ↓
                         앱: bills.submitter_name 으로 payees 대조 → 계좌 → 토스 송금
```

- 청구 폼이 받는 값은 **이름·항목·금액·영수증** 네 가지뿐이다. 계좌는 받지 않는다.
- 계좌는 관리자가 앱의 **계좌부(`payees`)** 에 이름↔계좌로 등록해 둔다.
- 영수증 이미지는 별도 R2 워커(`nanuri-bill`)의 `/upload` 에 위임한다.
  앱과 워커가 같은 URL 형식을 공유하므로 여기를 바꾸면 양쪽이 깨진다.

## 반드시 같이 고쳐야 하는 짝

한쪽만 바꾸면 조용히 깨지는 것들이다.

- **이름 정규화** — DB `payees_name_normalized_idx` (`lower(regexp_replace(name,'\s','','g'))`)
  ↔ 앱 `String.normalizedName`. 저장 전 공백 통일은 워커의 `submitterName` 처리
  ↔ 앱 `String.whitespaceNormalized`. 넷이 한 세트다.
  (PG의 `\s`는 U+00A0을 공백으로 안 본다. 그래서 저장 전에 통일한다.)
- **은행 목록** — `Features/Profile/Profile.swift`의 `koreanBanks`.
  토스 송금 딥링크 `supertoss://send?bank=...` 가 이 문자열을 그대로 쓴다.
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

## 빌드 / 검증

`xcode-select` 가 CommandLineTools 를 가리키고 있어 `xcodebuild` 가 그냥은 안 된다:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project NanuriAdmin.xcodeproj -scheme NanuriAdmin -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

마이그레이션 SQL 은 던져버릴 postgres 컨테이너에 `auth.users`·`supabase_realtime`·
`is_admin()` 만 스텁으로 만들어 두고 적용해 보면 실제로 검증된다.

## 주의

- `SUPABASE_SERVICE_ROLE_KEY` 는 RLS를 우회한다. 워커 시크릿에만 두고 앱·저장소에 넣지 않는다.
- 청구 폼은 **공개 URL** 이다. 방어는 IP당 분당 5건 + 영수증 필수/10MB/`image/*`
  + 금액 상한 1,000만 원이 전부다. 자세한 건 `worker/README.md`.
- 커밋 메시지는 제목·본문 모두 한국어로 쓴다.
