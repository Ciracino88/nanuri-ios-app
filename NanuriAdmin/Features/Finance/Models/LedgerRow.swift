import Foundation

/// **장부의 한 줄 = 항목 하나.**
///
/// 재정 목록이 이걸 그린다. 장부 정본이 `FinanceItem` 이므로 목록도 항목 단위다 —
/// 묶어 보낸 출금 하나는 여기서 여러 줄이 된다. 사람이 쓰던 엑셀도 항목 단위고,
/// 보고서·분석도 이미 그 단위로 센다.
///
/// **은행 증명이 뒤에 있으면**(모임) 그 거래를 `transaction` 으로 함께 들고 온다 —
/// 상세 화면이 은행 적요·대조 맥락을 보여주는 데 쓴다. 농협 수기 항목은 `nil`.
struct LedgerRow: Identifiable {
    let item: FinanceItem
    /// 이 항목이 나온 은행 거래(모임). 농협 수기 항목은 `nil`.
    let transaction: BankTransaction?

    var id: String { item.id.uuidString }
    var datetime: Date { item.datetime }
    var amount: Int { item.amount }
    var isDeposit: Bool { item.isDeposit }
    var isInternalTransfer: Bool { item.isInternalTransfer }

    /// 장부에 적힌 이름. 항목의 적요(사람 값)를 먼저, 비면 은행 적요로 떨어진다.
    var title: String? {
        let d = item.description?.trimmingCharacters(in: .whitespaces) ?? ""
        return d.isEmpty ? transaction?.description : d
    }
    var category: String? { item.category }
}
