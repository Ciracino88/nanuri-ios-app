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

/// 거래가 어디서 왔는가. **무엇을 고쳐도 되는지가 여기서 갈린다.**
enum TransactionSource: String, Codable {
    /// 사람이 앱에서 넣었다. 전부 사람이 적은 값이라 다 고칠 수 있다.
    /// 농협은 거래내역 파일이 안 나오므로 늘 이쪽이다.
    case manual
    /// 거래내역서에서 불러왔다. 금액·날짜·통장은 **통장의 기록**이라 잠근다 —
    /// 고치면 통장과 어긋나 대조가 뜻을 잃는다.
    case statement
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
    var datetime: Date
    let type: String
    var amount: Int
    var description: String?
    var category: String?
    var memo: String?
    var receiptUrls: [String]?
    let createdAt: Date?
    /// 없으면 `manual` — 이 칸이 생기기 전의 행(수기 장부 이관분)이 그렇다.
    var source: TransactionSource?

    var isDeposit: Bool { amount > 0 }

    /// 통장 기록이라 금액·날짜·통장을 잠가야 하는가.
    var isFromStatement: Bool { source == .statement }

    /// 통장 사이를 옮긴 돈인가. **합계·보고서·그래프에서 빼야 하는 거래다** —
    /// 장부 전체로 보면 나간 돈도 들어온 돈도 아니다.
    ///
    /// 안 빼면 그 달이 부풀어 보인다. 2026-08 이 실제로 그랬다: 장부상 지출
    /// 4,974,200 중 4,000,000 이 내부 이체라 진짜 지출(974,200)의 5.1배로 보였다.
    var isInternalTransfer: Bool { counterAccountId != nil }

    /// nil 안전 접근용.
    var receipts: [String] { receiptUrls ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, datetime, type, amount, description, category, memo, source
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
    /// 손으로 넣을 때는 분류를 그 자리에서 같이 받는다. 거래내역서로 불러온 것은 없다.
    var category: String? = nil
    var source: TransactionSource = .manual

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, description, category, source
        case ledgerId = "ledger_id"
        case accountId = "account_id"
        case counterAccountId = "counter_account_id"
    }
}

/// 거래 편집 저장 페이로드.
///
/// **금액·일시·통장까지 들어 있다.** 앱이 장부의 주인이 된 뒤로 이 셋도 고쳐야
/// 하기 때문이다. 다만 **거래내역서에서 불러온 거래는 그 셋을 잠근다** — 통장의
/// 기록이라 고치면 통장과 어긋난다.
///
/// **잠그는 판단은 화면이 아니라 `FinanceViewModel.saveTransactionEdits` 가 한다.**
/// 화면이 칸을 비활성으로 그리는 것만으로는 부족하다 — 규칙이 두 군데가 되고,
/// 두 군데는 언젠가 어긋난다.
struct TransactionEditUpdate: Encodable {
    let datetime: Date
    let amount: Int
    let description: String?
    let category: String?
    let memo: String?
    let receiptUrls: [String]
    let accountId: UUID
    let counterAccountId: UUID?

    enum CodingKeys: String, CodingKey {
        case datetime, amount, description, category, memo
        case receiptUrls = "receipt_urls"
        case accountId = "account_id"
        case counterAccountId = "counter_account_id"
    }
}

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

/// 보고서 한 줄을 구성하는 항목. 거래 자체이거나, 분할된 조각이다.
/// (통장 거래와 보고서 항목의 입도 차이를 흡수하는 중간 표현)
struct ReportLineItem {
    let datetime: Date
    let isDeposit: Bool
    let magnitude: Int          // 항상 양수
    let category: String?
    /// **이 줄이 스스로 갖는 적요.** 분할 조각만 갖는다.
    ///
    /// 거래 자체는 여기가 `nil` 이다 — 거래의 적요는 은행이 준 값이라
    /// `sourceDescription` 에 있고, 성격이 다르다. 아래 `reportLabel` 참고.
    let lineDescription: String?
    /// 이 줄이 나온 거래의 적요. 분할 조각이면 **부모 거래의** 것이다.
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

    /// 보고서 상세 명세의 **적요 칸에 찍히는 이름.** `적요 → 카테고리 → 거래 적요` 순이다.
    ///
    /// 적요가 먼저인데 **그 적요는 분할 조각만 갖는다.** 거래의 적요(은행이 준 값)를
    /// 여기 끌어오지 않는 건 의도다 — 그 값은 줄마다 다르므로 이름으로 쓰면
    /// "같은 날 · 같은 카테고리는 한 줄" 이라는 엑셀식 묶음이 통째로 무너진다.
    /// 분할 조각의 적요는 사람이 **그 줄을 위해** 적은 값이라 그렇지 않다.
    var reportLabel: String {
        if let d = lineDescription?.trimmingCharacters(in: .whitespaces), !d.isEmpty { return d }
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let s = sourceDescription?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s }
        return "미분류"
    }

    /// 같은 날 · 같은 방향의 다른 줄과 합쳐도 되는가.
    ///
    /// **사람이 이름을 준 줄만 합친다.** 적요도 카테고리도 없어서 은행이 준 적요로
    /// 떨어진 줄은 합치지 않는다 — 그 이름은 우연히 같을 수 있고, 합치면 아직
    /// 분류가 안 된 줄이 한 덩어리로 뭉쳐 "안 나눴다" 는 게 안 보인다.
    var mergesInReport: Bool {
        let d = lineDescription?.trimmingCharacters(in: .whitespaces) ?? ""
        let c = category?.trimmingCharacters(in: .whitespaces) ?? ""
        return !d.isEmpty || !c.isEmpty
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
