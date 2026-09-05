import Foundation

/// 항목 — **장부 정본, 사람의 판단.** (구 `TransactionSplit`)
///
/// 잔액·보고서·그래프가 전부 여기서 나온다. "거래의 분할"이 아니라 장부 그 자체라,
/// 부모 거래에 매달리지 않고 **자기 통장·시각·금액을 스스로 갖는다** — 농협 항목엔
/// 뒤에 거래가 없기 때문이다.
///
/// `sourceTransactionId` 가 신뢰수준의 표식이다.
///   차 있으면 → 은행 증명 뒤에 있음(모임 내역서 줄). 금액합·일시·통장 잠금.
///   비어 있으면 → 농협 수기. 사람의 말뿐이라 전부 편집 가능.
struct FinanceItem: Identifiable, Codable {
    var id: UUID
    /// 이 항목이 속한 통장.
    var accountId: UUID
    /// 모임 항목은 부모 거래의 시각을 복사, 농협 수기 항목은 사람이 고른 시각.
    var datetime: Date
    /// 부호(음수=출금). 잔액·보고서의 원천.
    var amount: Int
    /// 통장 사이 이체인가. **상대는 늘 '다른 통장 하나'**(통장 2개 고정)라 어느
    /// 통장인지 따로 안 적는다. 참이면 잔액 유도에서 상대 통장에 부호를 뒤집어
    /// 반영하고, 보고서·합계·그래프에서는 뺀다(수입도 지출도 아니므로).
    var isInternalTransfer: Bool
    var category: String?
    /// 이 항목의 적요. 사람이 그 줄을 위해 적는다.
    var description: String?
    /// 이 항목에 딸린 영수증. 매칭 때 대응 청구의 것을 복사해 온다.
    var receiptUrls: [String]?
    /// 이 항목이 나온 은행 거래. 없으면 농협 수기.
    var sourceTransactionId: UUID?
    var sortOrder: Int
    let createdAt: Date?

    var isDeposit: Bool { amount > 0 }

    /// 은행 증명이 뒤에 있는가. **편집 잠금의 근거** — 있으면 금액·일시·통장이
    /// 통장의 기록이라 잠근다.
    var isBankBacked: Bool { sourceTransactionId != nil }

    /// nil 안전 접근용.
    var receipts: [String] { receiptUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, datetime, amount, category, description
        case accountId = "account_id"
        case isInternalTransfer = "is_internal_transfer"
        case receiptUrls = "receipt_urls"
        case sourceTransactionId = "source_transaction_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

/// 항목을 넣는 페이로드. 매칭(모임, `sourceTransactionId` 채움)과 수기(농협, nil)가
/// 같은 형을 쓴다.
struct FinanceItemInsert: Encodable {
    var accountId: UUID
    var datetime: Date
    var amount: Int
    var isInternalTransfer: Bool = false
    var category: String? = nil
    var description: String? = nil
    var receiptUrls: [String] = []
    var sourceTransactionId: UUID? = nil
    var sortOrder: Int = 0

    enum CodingKeys: String, CodingKey {
        case datetime, amount, category, description
        case accountId = "account_id"
        case isInternalTransfer = "is_internal_transfer"
        case receiptUrls = "receipt_urls"
        case sourceTransactionId = "source_transaction_id"
        case sortOrder = "sort_order"
    }
}

/// 카테고리만 바꾸는 업데이트 페이로드. 여러 항목에 한 번에 붙일 때 쓴다.
struct CategoryPatch: Encodable {
    let category: String?
}

/// 항목의 **사람 값만** 바꾸는 업데이트. 은행 증명이 있는 항목(모임)도 이건 고칠 수
/// 있다 — 금액·일시·통장은 안 건드린다(잠금).
struct ItemFieldsUpdate: Encodable {
    let category: String?
    let description: String?
    let receiptUrls: [String]

    enum CodingKeys: String, CodingKey {
        case category, description
        case receiptUrls = "receipt_urls"
    }
}

/// 농협 수기 항목의 **전 필드** 업데이트. 은행 증명이 없어 금액·일시·통장까지 사람이
/// 고칠 수 있다.
struct ItemFullUpdate: Encodable {
    let accountId: UUID
    let datetime: Date
    let amount: Int
    let category: String?
    let description: String?
    let receiptUrls: [String]

    enum CodingKeys: String, CodingKey {
        case datetime, amount, category, description
        case accountId = "account_id"
        case receiptUrls = "receipt_urls"
    }
}
