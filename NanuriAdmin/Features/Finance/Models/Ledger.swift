import Foundation

/// 장부(통장).
///
/// 예전에는 `type` 이 `monthly` | `event` 두 가지였고 화면 골격이 그걸로 갈렸다
/// (행사 결산은 달 개념이 없어서 날짜 축도 지난달 비교도 안 그렸다).
/// **행사 결산을 쓰지 않기로 해서 `event` 를 걷어냈다.** 이제 장부는 전부 월별이다.
///
/// DB 의 `check (type in ('monthly','event'))` 는 그대로 두었다 — 제약을 좁히는
/// 마이그레이션은 얻는 게 없고, 혹시 남아 있는 옛 행이 있으면 그것만 깨진다.
struct Ledger: Identifiable, Codable {
    var id: UUID
    let name: String
    /// 늘 `"monthly"` 다. DB 컬럼이 not null 이라 들고만 있는다.
    let type: String
    let createdAt: Date?

    /// 앱이 만드는 장부의 `type`.
    static let monthlyType = "monthly"

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case createdAt = "created_at"
    }
}

struct LedgerInsert: Encodable {
    let name: String
    let type = Ledger.monthlyType
}
