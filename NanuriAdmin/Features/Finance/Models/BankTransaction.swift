import Foundation

/// 거래 — **은행이 증명한 사실.** 토스 거래내역서 한 줄이 곧 이 행이다.
///
/// 파싱으로만 생기고 **절대 편집하지 않는다**(불변). 금액·일시·통장은 통장의 기록이라
/// 고치면 통장과 어긋난다. 카테고리·적요(사람 값)·영수증은 여기 없다 — 전부 장부
/// 항목(`FinanceItem`)으로 갔다.
///
/// 이 표에 담기는 건 실질적으로 모임통장뿐이다. 농협은 인터넷뱅킹이 없어 내역서가
/// 안 나오므로 은행 증명이 없고, 농협의 입출금은 거래가 아니라 **수기 항목**으로
/// 들어간다(`FinanceItem.sourceTransactionId == nil`).
struct BankTransaction: Identifiable, Codable {
    var id: UUID
    /// 이 거래가 일어난 통장.
    var accountId: UUID
    var datetime: Date
    /// 은행 유형(이자입금·체크카드결제·ATM출금…).
    let type: String
    /// 은행이 말한 총액(부호, 출금은 음수). **대조의 기준** — 이 거래에서 나온
    /// 항목들의 합이 이 값과 같아야 한다.
    var amount: Int
    /// 은행 적요(예금주·가맹점 이름). 사람이 적는 적요가 아니라 은행이 준 값이다.
    var description: String?
    let createdAt: Date?

    var isDeposit: Bool { amount > 0 }

    enum CodingKeys: String, CodingKey {
        case id, datetime, type, amount, description
        case accountId = "account_id"
        case createdAt = "created_at"
    }
}

/// 거래내역서에서 불러온 은행 줄을 넣는 페이로드. **파싱 경로에서만** 쓴다.
struct BankTransactionInsert: Encodable {
    var accountId: UUID
    let datetime: Date
    let type: String
    let amount: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case datetime, type, amount, description
        case accountId = "account_id"
    }
}
