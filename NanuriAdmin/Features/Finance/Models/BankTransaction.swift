import Foundation

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
        case id, datetime, type, amount, description, category, source
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
    /// 손으로 넣을 때는 카테고리를 그 자리에서 같이 받는다. 거래내역서로 불러온 것은 없다.
    var category: String? = nil
    /// 청구서에 붙어 있던 영수증. **거래내역서로 넣을 때 같이 넘어온다.**
    ///
    /// 안 넘기면 청구서엔 영수증이 있는데 **영수증 부록 PDF 에는 안 나온다** —
    /// 그 부록은 `finance_transactions.receipt_urls` 를 모아 만들기 때문이다.
    var receiptUrls: [String] = []
    var source: TransactionSource = .manual

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, description, category, source
        case receiptUrls = "receipt_urls"
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
    let receiptUrls: [String]
    let accountId: UUID
    let counterAccountId: UUID?

    enum CodingKeys: String, CodingKey {
        case datetime, amount, description, category
        case receiptUrls = "receipt_urls"
        case accountId = "account_id"
        case counterAccountId = "counter_account_id"
    }
}
