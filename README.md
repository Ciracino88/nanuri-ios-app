# NanuriAdmin

교회 청년부 **나누리** 회계 담당자용 iOS 앱과, 청구를 받는 공개 웹 폼.

회비 청구를 카카오톡·구두로 받고 엑셀로 정리하던 걸 하나로 합쳤다.
청구자는 웹 폼에 넣고, 관리자는 푸시를 받아 앱에서 확인하고 토스로 송금한다.
결산은 통장 거래내역을 올려서 장부로 만들고 PDF 보고서로 뽑는다.

> **관리자 1인 전용이다.** 여러 사람이 쓰는 걸 전제하지 않았다.
> 회계 담당자 한 명만 로그인하고, 나머지는 로그인 없는 공개 폼만 쓴다.

## 하는 일

```
청구자 → 공개 웹 폼 → bills INSERT → APNs 푸시 → 관리자 앱
                                                    ↓
                        이름으로 계좌부 대조 → 계좌 → 토스 송금 → 완료 처리
```

청구 폼이 받는 값은 **이름 · 항목 · 금액 · 영수증** 네 가지뿐이다.
계좌는 안 받는다 — 관리자가 앱의 계좌부에 이름↔계좌로 등록해 두고, 접수된
이름을 그걸로 대조한다. 청구자가 매번 계좌를 적지 않아도 되고, 오타로 엉뚱한
곳에 보낼 일도 없다.

## 화면

앱은 탭 네 개다.

| 탭 | 하는 일 |
| --- | --- |
| **청구서** | 접수된 청구 목록. 카드를 누르면 상세 시트에서 영수증을 보고 송금·거절한다. 실시간으로 들어온다 |
| **재정** | 장부(통장)별 거래 관리. 토스뱅크 거래내역서 PDF 를 올리면 파싱해서 넣고, 월별 회계 보고서와 행사 결산을 PDF 로 뽑는다 |
| **계좌부** | 이름 ↔ 은행·계좌번호. 청구서와 사람을 잇는 곳이다 |
| **프로필** | 계정, 알림함, 로그아웃 |

**같은 사람의 대기중 청구서는 묶어서 한 번에 보낸다.** 청구서 탭의 선택 모드에서
고르면 금액을 합쳐 토스를 한 번만 연다. 사람이 다르면 못 묶는다 — 토스 딥링크가
수취인 한 명·금액 하나만 받는다.

## 구성

| 위치 | 내용 |
| --- | --- |
| `NanuriAdmin/` | SwiftUI 앱 (iOS 26.2+) |
| `worker/` | Cloudflare Worker. 공개 청구 폼 + Supabase 저장 + APNs 푸시 |
| `supabase/migrations/` | DB 스키마. 최신 것이 진실이고 앞의 것은 이력 |
| `scripts/` | 수기 엑셀 장부를 읽어 옮기는 파이썬 스크립트 |

앱 폴더는 Xcode 16 파일시스템 동기화 그룹이라 **새 `.swift` 는 폴더에 넣으면
자동 인식된다.** `project.pbxproj` 를 건드릴 일이 없다.

## 기술

- **앱** — SwiftUI, `@Observable` 이전의 `ObservableObject` 기반 MVVM,
  [supabase-swift](https://github.com/supabase/supabase-swift),
  [Kingfisher](https://github.com/onevcat/Kingfisher)(원격 이미지),
  GoogleSignIn(로그인)
- **서버** — Cloudflare Workers. 서비스 바인딩으로 R2 워커에 영수증을 위임한다
- **DB** — Supabase (Postgres + Realtime + Auth + Storage). 모든 테이블에 RLS

주요 테이블은 `bills`(청구서) · `payees`(계좌부) · `finance_ledgers`/
`finance_transactions`/`finance_splits`(장부) · `admins`(화이트리스트) ·
`device_tokens`(푸시) 다.

## 몇 가지 설계 판단

읽다가 "왜 이렇게 했지" 싶을 만한 것들이다. 자세한 건 `CLAUDE.md` 에 있다.

**`bills` 에 INSERT 정책이 없다.** 일부러 없앴다. 삽입은 워커의 `service_role`
만 할 수 있다. 금액 상한·영수증 필수 같은 검증을 **워커 한 곳에서만** 하기 위해서다.
정책을 열면 검증이 두 군데가 되고, 두 군데는 언젠가 어긋난다.

**RLS 는 전부 `is_admin()` 기준이다.** anon key 는 앱 바이너리에 들어 있고
Google provider 는 아무 구글 계정이나 로그인시킨다. `authenticated` 만으로는
아무것도 못 막는다.

**세션을 일부러 만료시키지 않는다.** 1인 전용이라 로그인 화면을 다시 볼 이유가 없다.
세션 판단은 네트워크를 안 타는 키체인 값으로만 한다 — 그러지 않으면 지하철에서
앱을 열 때마다 로그아웃된다.

**영수증은 제출 버튼을 누르기 전에 이미 올라가 있다.** 폼이 사진을 고르는 즉시
브라우저에서 축소해서(4MB → 300KB) 미리 올린다. 제출은 URL 만 넘기는 INSERT 하나다.

**알림함은 이 기기에만 있다.** DB 를 안 본다. 이 기기가 실제로 받은 푸시가 전부고,
기기를 바꾸면 비어 있다.

## 문서

| 파일 | 언제 보나 |
| --- | --- |
| [CLAUDE.md](CLAUDE.md) | **구조와 규칙.** 같이 고쳐야 하는 짝, 되돌리면 안 되는 것들 |
| [SETUP.md](SETUP.md) | 사람이 손으로 넣어야 하는 설정 (키 발급, 마이그레이션, 푸시) |
| [DESIGN.md](DESIGN.md) | 화면 규칙. **화면을 만들기 전에 본다** |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | 증상을 만났을 때. 원인과 왜 그렇게 고쳤는지 |
| [worker/README.md](worker/README.md) | 워커 라우트, 선행 업로드, 서명 |

화면 값은 전부 `Components/DesignSystem.swift` 의 `DS` 에 있다.
**화면 코드에 숫자를 직접 적지 않는다.**

## 빌드

`xcode-select` 가 CommandLineTools 를 가리키고 있으면 `xcodebuild` 가 그냥은
안 된다. 앞에 `DEVELOPER_DIR` 을 붙인다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project NanuriAdmin.xcodeproj -scheme NanuriAdmin -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

워커는 `wrangler` 가 전역 설치돼 있지 않아 `npx` 로 쓴다. 배포 전에 설정만
검증할 수 있다.

```bash
npx wrangler deploy --dry-run
```

푸시는 시뮬레이터에서 확인이 안 된다. **실기기가 필요하다.**

## 주의

- 진짜 비밀은 둘뿐이다 — `SUPABASE_SERVICE_ROLE_KEY`(RLS 우회)와
  `APNS_P8`(푸시 서명 개인키). 둘 다 저장소에 없다.
  `APNS_TEAM_ID`·`APNS_KEY_ID` 는 식별자라 `wrangler.toml` 에 그냥 적혀 있다.
- **청구 폼은 공개 URL 이고 요청 횟수 제한이 없다.** `[[ratelimits]]` 를 걸어뒀지만
  이 계정에서는 카운팅이 안 된다. 실제 방어는 영수증 필수 · 10MB · `image/*` ·
  금액 상한 1,000만 원뿐이다.
- **이름 사칭은 기술로 막지 않는다.** 관리자가 승인 전에 당사자에게 직접 확인하는
  것을 전제로 한 설계다.
