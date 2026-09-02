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

/// 통장. **장부는 하나인데 통장은 둘이다.**
///
/// 헌금을 받는 교회법인 농협통장과, 청구를 실시간으로 처리하는 토스 모임통장.
/// 매달 농협에서 모임으로 예산을 넘기고 월말 결산 때 남은 잔액을 돌려보낸다.
///
/// 이 표가 있는 이유는 **개시잔액이 살 곳**이 필요해서다. 거래마다 잔액을 저장하지
/// 않고 유도하므로 출발점이 어딘가에 있어야 한다.
struct Account: Identifiable, Codable {
    var id: UUID
    let ledgerId: UUID
    let name: String
    /// 장부가 이 통장을 적기 시작하는 시점에 이미 들어 있던 돈.
    let openingBalance: Int
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case ledgerId = "ledger_id"
        case openingBalance = "opening_balance"
        case sortOrder = "sort_order"
    }
}

/// 이 달에 한 방향으로 오간 내부 이체의 합.
///
/// 거래 한 줄이 양쪽 통장을 알고 있어서(`counter_account_id`) 방향은 **부호에서
/// 나온다.** 표에 따로 적어 두는 값이 아니라 `FinanceViewModel.internalTransferFlows`
/// 가 그때그때 세는 값이다.
struct AccountFlow: Identifiable {
    /// 보낸 통장 → 받은 통장. 같은 방향끼리 합치려고 키로 쓴다.
    struct Direction: Hashable {
        let from: UUID
        let to: UUID
    }

    let direction: Direction
    let amount: Int

    var id: Direction { direction }
}

struct BankTransaction: Identifiable, Codable {
    var id: UUID
    var ledgerId: UUID?
    /// 이 거래가 일어난 통장.
    var accountId: UUID
    /// 내부 이체일 때 **상대 통장**. 비어 있으면 실제 수입·지출이다.
    ///
    /// 농협에서 모임으로 돈을 옮기는 건 **한 사건인데 통장 둘에 걸친다.** 두 줄로
    /// 적으면 그 둘이 같은 사건이라는 걸 따로 짝지어야 하고, 짝이 깨지면 조용히
    /// 틀어진다. 한 줄이 양쪽을 알면 그런 일이 없다.
    var counterAccountId: UUID?
    let datetime: Date
    let type: String
    let amount: Int
    let description: String?
    var category: String?
    var memo: String?
    var receiptUrls: [String]?
    let createdAt: Date?

    var isDeposit: Bool { amount > 0 }

    /// 통장 사이를 옮긴 돈인가. **합계·보고서·그래프에서 빼야 하는 거래다** —
    /// 장부 전체로 보면 나간 돈도 들어온 돈도 아니다.
    ///
    /// 안 빼면 그 달이 부풀어 보인다. 2026-08 이 실제로 그랬다: 장부상 지출
    /// 4,974,200 중 4,000,000 이 내부 이체라 진짜 지출(974,200)의 5.1배로 보였다.
    var isInternalTransfer: Bool { counterAccountId != nil }

    /// nil 안전 접근용.
    var receipts: [String] { receiptUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, datetime, type, amount, description, category, memo
        case ledgerId = "ledger_id"
        case accountId = "account_id"
        case counterAccountId = "counter_account_id"
        case receiptUrls = "receipt_urls"
        case createdAt = "created_at"
    }
}

struct BankTransactionInsert: Encodable {
    var ledgerId: UUID? = nil
    var accountId: UUID? = nil
    var counterAccountId: UUID? = nil
    let datetime: Date
    let type: String
    let amount: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, description
        case ledgerId = "ledger_id"
        case accountId = "account_id"
        case counterAccountId = "counter_account_id"
    }
}

/// 거래 편집 저장 시 카테고리·메모·영수증을 한 번에 반영하기 위한 업데이트 페이로드.
struct TransactionEditUpdate: Encodable {
    let category: String?
    let memo: String?
    let receiptUrls: [String]

    enum CodingKeys: String, CodingKey {
        case category, memo
        case receiptUrls = "receipt_urls"
    }
}

/// 거래 분할 항목. 하나의 통장 거래를 여러 회계 항목으로 쪼갤 때 사용.
struct TransactionSplit: Identifiable, Codable {
    var id: UUID
    let transactionId: UUID
    var amount: Int
    var category: String?
    var memo: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, amount, category, memo
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

struct TransactionSplitInsert: Encodable {
    let transactionId: UUID
    let amount: Int
    let category: String?
    let memo: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case amount, category, memo
        case transactionId = "transaction_id"
        case sortOrder = "sort_order"
    }
}

/// 보고서 한 줄을 구성하는 항목. 거래 자체이거나, 분할된 조각이다.
/// (통장 거래와 보고서 항목의 입도 차이를 흡수하는 중간 표현)
struct ReportLineItem {
    let datetime: Date
    let isDeposit: Bool
    let magnitude: Int          // 항상 양수
    let category: String?
    let memo: String?
    let sourceDescription: String?

    /// 묶을 때 쓰는 카테고리 이름. 비어 있으면 **"미분류"** 다.
    ///
    /// 보고서(`FinanceReportExporter`)와 분석 화면(`SpendingDetailView`)이 같은
    /// 이름으로 묶어야 두 곳의 합계가 어긋나지 않는다. 빈 카테고리를 버리지 않고
    /// 한 덩어리로 모으는 것도 그래서다 — 분류가 덜 된 달일수록 그 덩어리가 커야
    /// "아직 안 나눴다" 는 게 보인다.
    var categoryLabel: String {
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return "미분류"
    }
}

/// 카테고리 하나에 묶인 합계. 분석 화면의 막대와 목록이 같이 쓴다.
struct CategoryTotal: Identifiable {
    let name: String
    let amount: Int

    var id: String { name }
}

/// 앱에 보관 중인 원본 거래내역서 PDF
struct StatementFile: Identifiable {
    let url: URL
    let importedAt: Date

    var id: String { url.lastPathComponent }
}
