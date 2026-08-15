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
| 6 | 앱에 푸시 기능 구현 | ⬜ **코드 작업 (입력 아님)** |

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

## 6. 앱에 푸시 기능 구현 ⬜ (코드 작업)

**입력할 값이 아니라 아직 만들지 않은 기능이다.**

현재 앱에는 푸시가 전혀 구현돼 있지 않다 — 알림 권한 요청도, `registerForRemote‐
Notifications` 도, Push Notifications capability 도, 받은 디바이스 토큰을
`device_tokens` 테이블에 넣는 코드도 없다.

워커 쪽(`apns.js`, `device_tokens` 테이블, 시크릿 자리)만 미리 만들어져 있어서
절반만 있는 상태다. 워커는 청구가 들어올 때마다 빈 토큰 목록을 받고 조용히
아무것도 하지 않는다.

즉 **3~5번을 다 해도 앱 작업 없이는 푸시가 오지 않는다.**

필요한 작업:
- Xcode > Signing & Capabilities 에서 Push Notifications 추가
- 알림 권한 요청 + `registerForRemoteNotifications`
- 받은 토큰을 `device_tokens` 에 upsert (`environment` 는 debug 빌드면 `sandbox`)
- 시뮬레이터에서는 실제 APNs 토큰이 나오지 않으므로 실기기로 확인

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
