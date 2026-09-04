import Foundation

/// **장부 한 줄.** 거래 자체이거나, 분할 조각이다.
///
/// 재정 목록이 이걸 그린다. 예전에는 거래를 그렸는데, 그러면 묶어 보낸 출금 하나가
/// 한 줄로 뭉쳐서(`아침식사 외 8`) **목록만 통장 시점이고 보고서·분석은 장부 시점**
/// 이라 한 앱 안에 단위가 둘이 됐다. 사람이 쓰던 엑셀도 조각 단위다.
///
/// 통장과 한 줄씩 대조하는 일은 잃지 않는다 — 중복 방지도 월말 검산도 **데이터가
/// 하는 일**이고, 통장을 나란히 놓고 보는 자리는 거래내역서 확인 화면이 맡는다.
///
/// **내부 이체는 쪼개지 않는다.** 장부 줄이 아니라서 조각이 아예 없다.
struct LedgerRow: Identifiable {
    let transaction: BankTransaction
    /// `nil` 이면 이 줄이 거래 자체다 (분할이 없는 거래).
    let split: TransactionSplit?

    var id: String { split?.id.uuidString ?? transaction.id.uuidString }
    var datetime: Date { transaction.datetime }
    var isInternalTransfer: Bool { transaction.isInternalTransfer }

    /// 조각 금액은 **크기만** 저장돼 있다. 부호는 거래가 준다.
    var amount: Int {
        guard let split else { return transaction.amount }
        return transaction.isDeposit ? split.amount : -split.amount
    }
    var isDeposit: Bool { transaction.isDeposit }

    /// 장부에 적힌 이름. 조각이면 조각의 적요, 아니면 거래의 적요(은행 값)다.
    var title: String? { split?.description ?? transaction.description }
    var category: String? { split?.category ?? transaction.category }
}
