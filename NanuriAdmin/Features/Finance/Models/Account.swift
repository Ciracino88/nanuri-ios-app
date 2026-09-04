import Foundation

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
    /// **이 통장이 상대 내역서의 적요에 찍히는 이름**(예금주).
    ///
    /// 농협↔모임 이체는 반드시 모임통장을 지나므로 토스 내역서에 찍히는데, 토스는
    /// 상대 예금주 이름을 적요에 넣는다. 그래서 **적요가 이 이름이면 내부 이체다.**
    /// `name`('농협'·'모임')은 사람이 부르는 이름이라 이 자리에 못 쓴다.
    let statementAlias: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case ledgerId = "ledger_id"
        case openingBalance = "opening_balance"
        case statementAlias = "statement_alias"
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
