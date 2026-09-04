import Foundation

/// 거래 분할 항목. 하나의 통장 거래를 여러 회계 항목으로 쪼갤 때 사용.
///
/// `description` 이 **이 조각의 적요**다. 거래의 `description` 은 은행이 준 값이지만
/// 조각의 것은 사람이 그 줄을 위해 적는다 — 묶어 보내기로 한 번에 나간 출금을
/// 쪼개면 조각마다 받는 사람이 다르기 때문이다. 부모 거래의 적요 하나로는 그 다섯
/// 줄을 구분할 수 없다.
struct TransactionSplit: Identifiable, Codable {
    var id: UUID
    let transactionId: UUID
    var amount: Int
    var category: String?
    var description: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, amount, category, description
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

struct TransactionSplitInsert: Encodable {
    let transactionId: UUID
    let amount: Int
    let category: String?
    let description: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case amount, category, description
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

/// 카테고리만 바꾸는 업데이트 페이로드. 여러 항목에 한 번에 붙일 때 쓴다.
struct CategoryPatch: Encodable {
    let category: String?
}
