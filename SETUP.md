# 직접 입력해야 하는 것

관리자(사람)가 손으로 넣어야 하는 값만 모았다. 코드로 해결되는 건 여기 없다.

마지막 확인: 2026-08-15

---

## 요약

**앞으로 입력해야 하는 비밀은 딱 하나다 — `APNS_P8`.**

나머지는 파일에 적거나(비밀이 아님), 이미 끝났거나, 코드 작업이다.

| # | 할 일 | 상태 |
|---|---|---|
| 1 | Supabase 마이그레이션 적용 | ✅ 완료 |
| 2 | `SUPABASE_SERVICE_ROLE_KEY` 등록 | ✅ 완료 |
| 3 | Apple Developer 갱신 | ⬜ 확인 필요 |
| 4 | APNs 키 발급 → `APNS_KEY_ID` 파일에 기입 | ⬜ |
| 5 | `APNS_P8` 시크릿 등록 | ⬜ |
| 6 | Xcode 에서 Push Notifications capability 체크 | ⬜ **계정 활성화 후에** |

3~6을 다 해야 푸시가 온다. **하나라도 빠지면 알림은 오지 않는다.**
청구서 접수·저장 자체는 이미 동작하므로 급한 일은 아니다.

---

## 1. Supabase 마이그레이션 ✅

적용 완료. 재적용이 필요해지면:

```bash
cd /Users/ciracino88/Desktop/SwiftUI-Project/NanuriAdmin && read -rs "?DB 비밀번호: " SUPABASE_DB_PASSWORD && export SUPABASE_DB_PASSWORD && supabase db push --linked
```

DB 비밀번호는 Supabase Dashboard > Project Settings > Database > Database password.
`supabase db push` 를 그냥 실행하면 CLI 가 임시 로그인 롤을 만들려다 권한 오류로
실패하므로, 위처럼 `SUPABASE_DB_PASSWORD` 를 넘겨야 한다.

## 2. SUPABASE_SERVICE_ROLE_KEY ✅

등록 완료. 이 키는 RLS 를 통째로 우회하므로 앱이나 저장소에 절대 넣지 않는다.
다시 넣어야 하면 Supabase Dashboard > Project Settings > API Keys > Legacy API keys
탭의 `service_role` 값으로:

```bash
cd /Users/ciracino88/Desktop/SwiftUI-Project/NanuriAdmin/worker && npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
```

## 3. Apple Developer 갱신 ⬜

멤버십이 만료되면 Certificates, Identifiers & Profiles 접근이 완전히 막힌다.
그래서 4번(APNs 키 발급)이 불가능하다.

- 갱신: [developer.apple.com/account](https://developer.apple.com/account) > **Renew Membership**
  (또는 iPhone 의 Apple Developer 앱. 만료 후 1년 이내면 재구독 가능)
- 연회비 USD 99 (약 ₩129,000), 유예 기간 없음

**갱신됐는지 확인하는 가장 확실한 방법은 4번을 실제로 해보는 것이다.**
Keys 화면에 들어가 키를 만들 수 있으면 갱신된 것이다.

로컬 인증서는 멤버십이 끊겨도 남아 있으므로 판단 근거가 되지 않는다.

### 결제했는데 계정에는 아직 만료라고 나올 때

정상이다. 주문 번호를 받았다는 건 결제 승인이지 멤버십 활성화가 아니다.
Apple 은 둘을 따로 처리하고 **활성화까지 보통 24~48시간** 걸린다.
그 사이 개발자 계정에는 계속 만료로 표시된다.

- 결제 시점부터 48시간을 기다린다
- Program License Agreement 동의 대기가 걸려 있는지 확인한다.
  약관이 갱신되면 동의 전까지 계정이 제한 상태로 남는다
- 48시간이 지나도 그대로면 주문 번호를 갖고
  [Apple Developer Support](https://developer.apple.com/contact/) 에 문의한다

## 4. APNs 키 발급 → APNS_KEY_ID ⬜

[developer.apple.com/account](https://developer.apple.com/account)
→ **Certificates, Identifiers & Profiles** → **Keys** → **＋**
→ 이름 입력, **Apple Push Notifications service (APNs)** 체크
→ Continue → Register → **`.p8` 파일 다운로드**

> ⚠️ `.p8` 은 **딱 한 번만** 다운로드된다. 잃어버리면 키를 폐기하고 새로 만들어야 한다.
> 받은 파일은 안전한 곳에 보관할 것.

키 페이지에 표시되는 **Key ID**(10자리)를 `worker/wrangler.toml` 에 적는다:

```toml
APNS_KEY_ID = "여기에10자리"
```

`APNS_TEAM_ID` 는 이미 `23ULXV7A5W` 로 채워져 있다. 건드릴 필요 없다.

이 둘은 비밀이 아니라 식별자다. Team ID 는 배포되는 앱 바이너리 안에 들어가고
Xcode 화면에도 그대로 보인다. Key ID 도 키를 가리키는 번호일 뿐이다.
그래서 파일에 적고 커밋한다.

수정 후 배포:

```bash
cd /Users/ciracino88/Desktop/SwiftUI-Project/NanuriAdmin/worker && npx wrangler deploy
```

## 5. APNS_P8 시크릿 등록 ⬜

**이것만이 진짜 비밀이다.** 푸시를 서명하는 개인키라, 유출되면 남이 이 앱 이름으로
알림을 보낼 수 있다.

```bash
cd /Users/ciracino88/Desktop/SwiftUI-Project/NanuriAdmin/worker && npx wrangler secret put APNS_P8
```

물어보면 다운로드한 `.p8` 파일 내용을 **전체** 붙여넣는다.
`-----BEGIN PRIVATE KEY-----` 줄과 `-----END PRIVATE KEY-----` 줄까지 포함이다.

명령 뒤에 값을 직접 붙이지 말 것. 셸 히스토리에 남는다.

## 6. 앱 푸시 — Xcode 에서 capability 체크 ⬜

코드는 들어가 있다 (`App/PushManager.swift`). 알림 권한 요청, APNs 등록,
받은 토큰을 `device_tokens` 에 upsert 하는 것까지 되어 있다.

**남은 건 Xcode 에서 체크 하나다.**

Xcode > 프로젝트 선택 > TARGETS: NanuriAdmin > **Signing & Capabilities**
→ 좌상단 **＋ Capability** → **Push Notifications** 추가

이걸 해야 프로비저닝 프로파일에 `aps-environment` 가 들어간다. 없으면
`registerForRemoteNotifications()` 가 `didFailToRegisterForRemoteNotifications`
로 떨어진다. (앱은 그대로 동작하고 알림만 오지 않는다)

> ⚠️ **Apple 계정이 활성화된 뒤에 할 것.** 멤버십이 만료된 상태에서 capability 를
> 추가하면 프로파일을 다시 만들지 못해 **코드 서명이 깨지고 빌드가 안 된다.**
> 그래서 코드만 먼저 넣고 capability 는 남겨뒀다.

확인은 실기기로 해야 한다. 시뮬레이터에서는 실제 APNs 토큰이 나오지 않는다.
기기에서 앱을 켜고 알림 권한을 허용한 뒤, 청구 폼으로 한 건 넣어보면 된다.

잘 안 되면 워커 로그를 본다:

```bash
cd /Users/ciracino88/Desktop/SwiftUI-Project/NanuriAdmin/worker && npx wrangler tail
```

`APNs 설정 없음: ...` 이 찍히면 4·5번이 덜 된 것이고,
아무 로그도 없으면 `device_tokens` 가 비어 있는 것이다 (앱에서 토큰 등록 실패).

---

## 참고: 비밀이 아닌 것

혼동을 줄이려고 명시해 둔다. 아래는 저장소에 그대로 들어 있고, 들어 있어도 된다.

| 값 | 왜 괜찮은가 |
|---|---|
| `APNS_TEAM_ID` | 앱 바이너리의 embedded.mobileprovision 에 들어감. Xcode 에도 표시됨 |
| `APNS_KEY_ID` | 키를 가리키는 번호. `.p8` 없이는 무용 |
| `APNS_TOPIC` | 앱 번들 ID |
| `SUPABASE_URL` | 프로젝트 주소 |
| 앱의 Supabase anon key | 공개 전제. 보호는 RLS + `is_admin()` 화이트리스트가 한다 |

진짜 비밀은 둘뿐이다 — `SUPABASE_SERVICE_ROLE_KEY`, `APNS_P8`.
