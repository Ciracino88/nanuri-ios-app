# 디자인 가이드라인

이 문서는 **이미 앱에 있는 규칙을 적은 것**이지 새로 정한 취향이 아니다.
값은 전부 `NanuriAdmin/Components/DesignSystem.swift` 의 `DS` 에 이름으로 들어 있다.
**화면 코드에 숫자를 직접 적지 않는다.** 필요한 값이 없으면 먼저 `DS` 에 이름을 붙인다.

관리자 1인이 쓰는 앱이고, 화면마다 정보 밀도가 높다. 그래서 아래 규칙들은
"예뻐 보이려고"가 아니라 **한 화면에 많은 정보를 넣고도 읽히게** 하려고 있는 것이다.

---

## 1. 화면의 뼈대

모든 목록 화면은 같은 구조다.

```
화면 배경 systemGroupedBackground
└─ 카드 systemBackground · radius 16 · 그림자 6%
```

- 목록은 `List` + `.listStyle(.plain)` + `.screenBackground()`
- 행은 `BillRowView` 처럼 **카드 하나**다. `.cardStyle()` + `.cardRow()`
- `Form` 은 **입력 화면에서만** 쓴다 (`PayeeEditView`, `TransactionEditView`).
  목록에는 쓰지 않는다 — 카드 구조와 섞이면 두 가지 배경이 한 화면에 나온다.

```swift
List(bills) { bill in
    BillRowView(bill: bill)      // 내부에서 .cardStyle()
        .cardRow()               // 목록 행일 때의 여백 + List 장식 제거
}
.listStyle(.plain)
.screenBackground()
```

`.cardRow()` 가 구분선을 지우는 건 취향이 아니다. 카드가 자기 그림자를 갖고 있어서
구분선이 같이 그려지면 카드 밑에 선이 겹쳐 보인다.

## 2. 여백

| 이름 | 값 | 쓰는 곳 |
| --- | --- | --- |
| `DS.Spacing.screen` | 16 | 화면 좌우 여백, 카드 안쪽 여백 |
| `DS.Spacing.cardGap` | 6 | 세로로 이어지는 카드 사이(위아래 각각) |
| `tight` / `small` / `medium` / `section` | 4 / 8 / 12 / 20 | 요소 사이 |

화면 좌우 여백과 카드 안쪽 여백이 **둘 다 16** 인 게 중요하다. 이게 어긋나면
카드 안 글자와 화면 제목의 세로선이 안 맞는다.

글이 긴 카드는 `.cardStyle(padding:)` 으로 안쪽 여백만 키운다. 카드 모양·그림자는
그대로 둔다.

## 3. 글자

**텍스트에는 고정 pt 를 쓰지 않는다.** 시맨틱 폰트만 쓴다 (Dynamic Type 대응).
고정 pt(`.font(.system(size:))`)는 **SF Symbol 아이콘 전용**이다. 지금 코드도 예외 없이 그렇다.

| 역할 | 폰트 | 모디파이어 |
| --- | --- | --- |
| 화면 제목 | `.largeTitle` bold | `AdminHeaderView` 또는 `.navigationTitle` |
| 카드 제목 | `.title3` bold | `.cardTitle()` |
| 큰 선택 행 제목 | `.headline` | 장부 게이트처럼 행이 크고 개수가 적은 목록 |
| 강조 금액 | `.title3` bold | — |
| 행 제목 · 사람 이름 | `.subheadline` medium | `.rowTitle()` |
| 보조 금액 · 값 | `.subheadline` semibold | — |
| 설명 · 날짜 · 계좌 줄 | `.caption` + `.secondary` | `.rowSubtext()` |
| 칩 · 상태 배지 | `.caption2` | `.tagChip(color:)` |

`.body`(17pt)는 본문에 거의 쓰지 않는다. 한 화면에 들어가는 정보가 많아
`.subheadline`(15pt)·`.caption`(12pt)이 실질적인 본문 크기다.

`.footnote` / `.title2` 는 산발적으로 남아 있는 값이다. **새로 쓰지 말 것.**
위 표의 역할 중 하나로 고른다.

## 4. 아이콘

아이콘만 고정 pt 다. 네 단계뿐이다.

| `DS.Icon` | 값 | 쓰는 곳 |
| --- | --- | --- |
| `inline` | 15 | 카드 안 작은 액션 버튼(`BillRowView` 의 36×36 버튼) |
| `action` | 18 | 헤더 · 툴바 액션 |
| `feature` | 22 | 목록 행이나 카드의 대표 아이콘 |
| `placeholder` | 46 | 빈 화면 일러스트 |

## 5. 색

색은 **장식이 아니라 뜻**이다. 화면이 달라도 같은 뜻이면 같은 색이어야 한다.

| `DS.Palette` | 색 | 뜻 |
| --- | --- | --- |
| `deposit` | 파랑 | 입금 · 주요 동작(송금) · 첨부 |
| `withdrawal` | 빨강 | 출금 · 되돌릴 수 없는 동작(삭제 · 거절 · 로그아웃) |
| `pending` | 주황 | 대기 · 주의(계좌 미등록) |
| `done` | 초록 | 완료(송금됨) |

**빨강은 돈이 나가거나 무언가 사라질 때만 쓴다.** 강조하고 싶다는 이유로 쓰면
사용자가 위험 신호를 무시하기 시작한다.

이 넷 말고 다른 색을 화면에 들이지 않는다. 색을 늘리면 색이 뜻을 잃는다.

칩은 두 종류뿐이다 (`Components/ChipStyle.swift`).
- `.tagChip(color:)` — 읽기 전용 라벨. 배경은 그 색의 12%.
- `.selectableChip(isSelected:)` — 탭으로 토글.

배경 12%는 카드 위에서 글자가 읽히는 최소치다. 더 진하면 칩이 버튼처럼 보인다.

## 6. 컨트롤

- **세그먼트 전환**은 항상 `PillPicker`. `Picker(.segmented)` 를 쓰지 않는다 —
  개수 배지를 같이 보여줘야 한다.
- **카드 안 액션 버튼**은 36×36, radius 10(`DS.Radius.button`), 아이콘 15pt.
- **헤더 액션 버튼**은 52×44 를 캡슐 하나로 묶고 사이에 `Divider` 를 넣는다
  (`AdminHeaderView`).
- 되돌릴 수 없는 동작(삭제·로그아웃)은 **확인을 한 번 받는다.** `alert` 또는
  `confirmationDialog`.

## 7. 움직임

두 가지만 쓴다.

| | 값 | 쓰는 곳 |
| --- | --- | --- |
| `DS.Motion.list` | spring(0.4, 0.8) | 목록 항목이 들고 날 때 |
| `DS.Motion.control` | spring(0.3, 0.7) | 컨트롤 선택이 바뀔 때 |

새 곡선을 만들지 않는다. 화면마다 미묘하게 다른 속도는 눈에 띄지 않으면서
앱을 조잡하게 만든다.

## 8. 빈 상태

`EmptyStateView` 를 쓴다. 아이콘은 선택이고, **무엇을 하면 채워지는지**를 적는다.

```swift
EmptyStateView(
    title: "등록된 계좌가 없어요",
    icon: "person.text.rectangle",
    message: "청구자 이름과 계좌를 미리 등록해 두면\n청구서가 들어올 때 자동으로 연결돼요."
)
```

## 9. 말투

- 화면의 모든 글은 **한국어 해요체**다. "저장되었습니다" 가 아니라 "저장했어요".
- 오류도 사람 말로 적는다. `error.localizedDescription` 을 그대로 화면에 올리는 건
  마지막 수단이다.
- 빈 상태·오류는 **다음에 뭘 하면 되는지**까지 적는다.

---

## 다음에 할 것

2026-08-15 기준. 위쪽 규칙은 **이미 코드에 반영돼 있고**, 아래는 아직 안 된 것들이다.
큰 것부터 적었다.

### 1. 헤더를 하나로 (구조 결정이 필요함)

청구서 탭만 `AdminHeaderView` + `navigationBarHidden` 이고, 재정 · 계좌부는
`.navigationTitle` + 툴바다. 프로필 · 로그아웃 · 아바타가 청구서 탭에만 있어서
생긴 차이다.

**그냥 통일하면 프로필과 로그아웃이 갈 곳이 없어진다.** 먼저 정해야 할 것:

- 네 번째 탭(설정)을 만들어 프로필 · 로그아웃을 거기로 옮기는가, 아니면
- 모든 화면 툴바에 아바타 버튼을 두는가

정하기 전에는 손대지 않는다. 새 화면은 그동안 `.navigationTitle` 쪽을 따른다.

### 2. 다크 모드 점검 (한 번도 안 봤다)

카드가 `systemBackground`, 배경이 `systemGroupedBackground` 인데 **다크 모드에서는
이 둘의 명도 관계가 라이트와 반대**가 된다. 게다가 카드를 띄우는 수단이 6% 검정
그림자 하나뿐이라, 어두운 배경 위에서는 그림자가 사실상 안 보인다.
→ 다크에서 카드 경계가 흐려질 가능성이 높다. 실제로 켜 보고, 필요하면 다크에서만
아주 옅은 테두리를 주는 식으로 보완한다.

### 3. 아이콘 전용 버튼에 접근성 라벨이 하나도 없다

`accessibilityLabel` 사용처가 **0곳**이다. `BillRowView` 의 36×36 버튼들
(영수증 · 송금 · 거절 · 삭제), `AdminHeaderView` 의 새로고침 · 로그아웃이 전부
아이콘뿐이라 VoiceOver 가 심볼 이름을 읽거나 아무 것도 못 읽는다.
**송금과 거절이 나란히 있는 화면**이라 이건 편의 문제가 아니라 사고 위험이다.

### 4. 큰 글씨(Dynamic Type)에서 카드가 버티는지

`BillRowView` 아래쪽은 금액 + 버튼 4개가 한 `HStack` 이다. 글씨를 키우면 금액이
줄바꿈되거나 버튼이 밀릴 수 있다. 접근성 텍스트 크기로 한 번 훑어본다.

### 5. 남은 값 정리 (기계적)

- `.footnote` / `.title2` / `.body` 가 한두 군데씩 남아 있다 (`ProfileEditView`,
  `TossResultView`, `LoginView`).
- 시트 안 아이콘 크기 20 · 24 · 26 · 30 (`TossResultView`, `ProfileEditView`,
  `TransactionEditView`) → `DS.Icon` 으로.

### 6. 계좌부 탭은 아직 눈으로 못 봤다

빌드만 확인했다. `searchable` + 카드 행 + `swipeActions` 조합은 실제로 띄워 봐야
여백이 맞는지 안다.
