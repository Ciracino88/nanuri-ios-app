# 고쳐 본 것들

증상이 났을 때 **원인이 무엇이었고 왜 그렇게 고쳤는지**를 남긴다.
"이렇게 하세요"가 아니라 "이래서 이렇게 됐다"를 적는 문서다.
설정값은 `SETUP.md`, 화면 규칙은 `DESIGN.md`, 구조는 `CLAUDE.md` 에 있다.

새 항목은 **맨 위에** 붙인다.

---

## 2026-08-19 · 영수증 사진이 매번 다시 받아지고 메모리를 크게 썼다

**증상**
- 영수증 시트를 닫았다 다시 열면 사진을 처음부터 다시 받았다.
- 목록이 갱신되는 동안(Realtime) 사진이 아예 안 뜨는 일이 있었다.
- 썸네일 한 장에도 원본 해상도만큼의 메모리를 썼다.

**원인**
`AsyncImage` 는 세 가지를 안 해 준다.
1. 받은 이미지를 안 들고 있는다. 뷰가 사라지면 그걸로 끝이다.
2. 뷰가 다시 만들어지면 **로딩을 처음부터 다시 시작한다.** 부모가 자주 재렌더되는
   화면(실시간 목록)에서는 매번 리셋돼서 결국 아무것도 못 그린다. 아바타에서 먼저
   겪고 `CachedAvatarImage` 를 따로 만들었던 게 이 문제였다.
3. **원본 해상도로 디코드한다.** 폼이 올리는 영수증은 긴 변 1600px 라 파일은
   300KB 남짓이지만, 비트맵으로 펴면 1600×1200×4byte ≈ 7.7MB 다. 90pt 썸네일에
   그 전부를 편다.

**해결** — `Components/RemoteImage.swift` 의 `CachedAsyncImage` 로 전부 옮겼다.
- **메모리 → 디스크 → 네트워크** 순으로 찾는다. 메모리 캐시는 뷰가 **동기로** 볼 수
  있어야 해서 actor 밖의 `NSCache` 에 둔다. 그래야 다시 열 때 첫 프레임부터 그려진다.
- **다운샘플링** — `CGImageSourceCreateThumbnailAtIndex` 로 그릴 크기만큼만 디코드한다.
  `kCGImageSourceCreateThumbnailWithTransform` 을 켜야 세로로 찍은 영수증이 안 눕는다.
- 디스크에는 **줄여 놓은 것**을 저장한다. 원본을 두면 앱을 켤 때마다 다시 줄여야 한다.
- 영수증 URL 은 업로드마다 새로 생기고 **같은 URL 의 내용은 안 바뀐다.** 그래서 URL 을
  키로 계속 캐시해도 안전하다. 서버가 `Cache-Control` 을 안 줘도 우리 쪽에서 다시 안 받는다.
- 손가락으로 확대하는 화면(`TransactionEditView` 의 미리보기)만 `maxDimension: nil` 로
  원본을 쓴다. 줄여 놓으면 확대했을 때 뭉갠 게 보인다.

**재발 방지** — 앱에서 `AsyncImage` 를 직접 쓰지 않는다. 원격 이미지는 전부
`CachedAsyncImage` 다. 크기 힌트(`maxDimension`)를 빼먹으면 다운샘플링이 안 되므로,
확대 화면이 아니면 반드시 준다.

**남은 것** — R2 응답에 `Cache-Control` 이 없다 (`SETUP.md` 8번). 우리 디스크 캐시가
지워진 뒤의 첫 로딩에만 영향이 있어서 급하지는 않지만, 붙여 두면 그 경우에도 안 받는다.

### 곁가지: `Phase` 를 제네릭 뷰 안에 중첩하면 컴파일이 안 된다

`CachedAsyncImage<Content>` 안에 `enum Phase` 를 두고 클로저에 넘겼더니
`generic parameter 'Content' could not be inferred` 가 났다. 클로저 본문의 타입을
`Content` 로 추론해야 하는데, 그 본문이 쓰는 `Phase` 가 `CachedAsyncImage<Content>.Phase`
라서 순환이 생긴다. `Phase` 를 타입 밖으로 빼면 풀린다. SwiftUI 의 `AsyncImagePhase`
가 `AsyncImage` 밖에 나와 있는 것도 같은 이유다.

---

## 2026-08-19 · 탭을 한 번 옮기면 실시간 반영이 죽었다

**증상** 청구서가 들어와도 목록이 그대로였다. 그런데 탭을 나갔다 들어오면 보였다.
그래서 "가끔 늦는다" 처럼 보이고 원인을 못 잡았다.

**원인** 구독을 `BillListView` 의 `.task` 안에서 통째로 돌리고 있었다.
1. 탭을 떠나면 화면이 사라지면서 `.task` 가 **취소**된다.
2. `AsyncStream` 이 끝나고 `onTermination` 이 postgres_changes 콜백을 떼어 간다.
3. 그런데 **채널은 `subscribed` 상태로 SDK 캐시에 남는다.**
4. 탭에 돌아와 `supabase.channel("bills-realtime")` 을 다시 부르면 토픽이 같으니
   캐시된 그 채널이 그대로 오고, **이미 구독된 채널에는 콜백을 못 붙인다.**
   SDK 는 경고만 찍고 빈 구독을 돌려준다 (`RealtimeChannelV2._onPostgresChange`).

디버그 빌드면 이 경고가 뜬다 — 이게 보이면 이 증상이다:
```
Cannot add "postgres_changes" callbacks for "realtime:bills-realtime" after `subscribe()`.
```

증상이 가려졌던 이유도 여기 있다. 같은 `.task` 가 `fetchBills()` 를 같이 불렀기 때문에
**탭을 오갈 때는 목록이 맞았다.** 켜 둔 채 가만히 있을 때만 안 들어왔다.

**해결** 구독 태스크와 채널을 `BillViewModel` 이 갖고, 뷰 생명주기와 뗐다.
`subscribeToRealtime()` 은 두 번째 호출부터 아무 일도 안 한다.
백그라운드에서 웹소켓이 끊긴 동안 놓친 변경은 `scenePhase` 가 `.active` 로 돌아올 때
한 번 다시 불러 맞춘다.

**재발 방지** 실시간 구독을 화면의 `.task` 로 되돌리지 않는다. 콜백은 언제나
`subscribe()` **전에** 붙어야 하고, 같은 토픽으로 다시 구독할 일이 생기면
`removeChannel` 로 캐시에서 지운 뒤 새로 만든다.

---

## 2026-08-19 · 새로고침 버튼을 걷어내니 빈 화면에서 새로고침할 방법이 없어졌다

**증상** 헤더의 새로고침 버튼을 없애고 당겨서 새로고침(`.refreshable`)으로 바꿨더니,
목록이 **비어 있을 때** 새로고침이 아예 안 됐다.

**원인** `.refreshable` 은 스크롤되는 것에만 붙는다. 빈 상태는 `EmptyStateView` 한 장이라
스크롤 대상이 없다. 게다가 내용이 화면보다 짧으면 `ScrollView` 라도 기본값으로는
튕기지 않아 당길 수가 없다.

**해결** `DS` 에 `pullToRefresh` 를 넣었다. 빈 상태를 `ScrollView` 로 감싸고
`containerRelativeFrame(.vertical)` 로 화면 높이를 채운 뒤 `scrollBounceBehavior(.always)`
로 튕김을 강제한다. 청구서·계좌부·재정의 빈 화면에 전부 붙였다.

**재발 방지** 버튼 없이 당겨서 새로고침만 두는 화면은 **빈 상태도 당길 수 있는지**를
같이 확인한다 (`DESIGN.md` 1번).

---

## 2026-08-19 · 묶어서 송금은 왜 "같은 사람"만 되나

버그는 아니고, 다시 물어보게 될 제약이라 남긴다.

토스 딥링크 `supertoss://send?bank=&accountNo=&amount=` 는 **수취인 한 명, 금액 하나**만
받는다. 여러 사람에게 한 번에 보내는 스킴은 없다. 그래서 묶음은 같은 사람 안에서만
만들고, 사람이 다르면 앱을 사람 수만큼 열었다 돌아와야 한다 (그건 안 한다).

승인은 `updateStatus(billIds:)` 로 **한 요청**에 처리한다. 건별로 나눠 쏘면 중간에
끊겼을 때 일부만 완료로 남아, 나머지가 다시 청구된 것처럼 보인다.
