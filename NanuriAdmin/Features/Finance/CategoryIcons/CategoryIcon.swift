import SwiftUI

/// **카테고리에 붙일 수 있는 아이콘 하나.**
///
/// 그림은 SF Symbols 가 아니라 **에셋 카탈로그에 심은 Hicon(Linear) 벡터**다
/// (`Assets.xcassets/CategoryIcons/`, 네임스페이스 폴더). 24×24 그리드에 가는 선
/// 하나로 그려져 DESIGN.md §6 의 결(regular·가는 stroke)과 맞고, imageset 을
/// **template 렌더링**으로 심어 색은 `foregroundColor` 가 정한다 — 뜻이 붙은
/// 시맨틱 색(§5)을 그대로 얹을 수 있다.
///
/// `id` 가 곧 에셋 이름이고 UserDefaults 에 저장되는 키다. **한 번 정한 `id` 는
/// 바꾸지 않는다** — 바꾸면 이미 그 아이콘을 고른 카테고리가 빈 그림이 된다.
struct CategoryIcon: Identifiable, Equatable {
    /// 에셋 이름이자 저장 키 (예: `heart`). 폴더 네임스페이스가 앞에 붙는다.
    let id: String
    /// 피커·보조기술이 읽는 한국어 이름.
    let label: String
    /// 피커에서 묶어 보여줄 무리.
    let group: Group

    /// 네임스페이스가 붙은 실제 에셋 이름. `Image(_:)` 에 이대로 넘긴다.
    var assetName: String { "CategoryIcons/\(id)" }

    enum Group: String, CaseIterable, Identifiable {
        case heart = "마음"
        case people = "사람"
        case food = "음식"
        case money = "돈"
        case place = "장소"
        case record = "기록"
        case media = "미디어"
        var id: String { rawValue }
    }
}

/// 심어 둔 Hicon 목록. **피커가 이걸 그린다.**
///
/// 에셋 카탈로그에 있는 imageset 과 이 목록이 **짝**이다 — 여기 있는 `id` 는
/// `Assets.xcassets/CategoryIcons/<id>.imageset` 이 반드시 있어야 하고, 없으면
/// 피커에 빈 칸이 뜬다. 새 아이콘을 늘리려면 imageset 을 심고 여기 한 줄을 더한다.
enum CategoryIconCatalog {
    static let all: [CategoryIcon] = [
        // 마음·헌금
        .init(id: "heart", label: "사랑", group: .heart),
        .init(id: "like", label: "좋아요", group: .heart),
        .init(id: "gift", label: "선물", group: .heart),
        .init(id: "award", label: "상", group: .heart),
        .init(id: "star", label: "별", group: .heart),
        // 사람·모임
        .init(id: "group", label: "모임", group: .people),
        .init(id: "profile", label: "사람", group: .people),
        .init(id: "education", label: "교육", group: .people),
        // 음식
        .init(id: "cup", label: "컵", group: .food),
        .init(id: "cupTea", label: "차", group: .food),
        // 돈
        .init(id: "wallet", label: "지갑", group: .money),
        .init(id: "card", label: "카드", group: .money),
        .init(id: "dollar", label: "현금", group: .money),
        .init(id: "bag", label: "장보기", group: .money),
        .init(id: "ticket", label: "티켓", group: .money),
        // 장소·이동
        .init(id: "home", label: "집", group: .place),
        .init(id: "location", label: "위치", group: .place),
        .init(id: "map", label: "지도", group: .place),
        // 기록·소통
        .init(id: "document", label: "문서", group: .record),
        .init(id: "calendar", label: "달력", group: .record),
        .init(id: "clock", label: "시간", group: .record),
        .init(id: "tag", label: "태그", group: .record),
        .init(id: "category", label: "분류", group: .record),
        .init(id: "message", label: "메시지", group: .record),
        .init(id: "send", label: "보내기", group: .record),
        .init(id: "search", label: "검색", group: .record),
        .init(id: "setting", label: "설정", group: .record),
        // 미디어
        .init(id: "music", label: "음악", group: .media),
        .init(id: "camera", label: "사진", group: .media),
        .init(id: "work", label: "가방", group: .media),
    ]

    /// `id` 로 하나 찾기. 저장된 키를 그림으로 되돌릴 때 쓴다.
    static func icon(id: String?) -> CategoryIcon? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// 무리별로 묶어 (무리 정의 순서대로) 돌려준다. 피커가 섹션으로 그린다.
    static var grouped: [(group: CategoryIcon.Group, icons: [CategoryIcon])] {
        CategoryIcon.Group.allCases.map { g in
            (g, all.filter { $0.group == g })
        }
    }
}

/// 카테고리 아이콘을 그리는 공용 뷰. **template 렌더링**이라 색은 밖에서 준다.
///
/// 그림이 없으면(아이콘 미지정) 아무것도 안 그린다 — 자리를 비워 둘지 말지는
/// 부르는 쪽이 정한다.
struct CategoryIconImage: View {
    let iconId: String
    var body: some View {
        Image("CategoryIcons/\(iconId)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}
