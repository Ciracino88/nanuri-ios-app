import Foundation

extension FinanceViewModel {

    // MARK: - 잔액은 저장하지 않고 유도한다

    /// 한 통장의 잔액. 개시잔액에서 시작해 그 통장을 지나간 돈을 전부 더한다.
    ///
    /// **내부 이체는 한 줄이 양쪽 통장에 걸친다.** `accountId` 쪽은 적힌 부호 그대로,
    /// `counterAccountId` 쪽은 **부호를 뒤집어** 더해야 두 통장 잔액이 모두 맞는다.
    /// (농협에서 −400만이면 모임에서는 +400만이다)
    func balance(of account: Account, asOf date: Date? = nil) -> Int {
        var sum = account.openingBalance
        for tx in transactions {
            if let date, tx.datetime > date { continue }
            if tx.accountId == account.id {
                sum += tx.amount
            } else if tx.counterAccountId == account.id {
                sum -= tx.amount
            }
        }
        return sum
    }

    /// 총 재정 = 모든 통장의 잔액 합.
    ///
    /// 내부 이체는 한쪽에서 빠지고 다른 쪽에 더해져 **저절로 상쇄된다.**
    /// 그래서 따로 걸러낼 필요가 없다.
    func totalBalance(asOf date: Date? = nil) -> Int {
        accounts.reduce(0) { $0 + balance(of: $1, asOf: date) }
    }

    /// 이 달에 **통장 사이를 오간 돈.** 보낸 통장 → 받은 통장 방향별로 합친다.
    ///
    /// `filtered` 에서 내부 이체만 골라 낸 것이라 합계·보고서가 쓰는
    /// `filteredExternal` 의 **여집합**이다. 통장 화면만 이걸 본다 — 통장별 잔액과
    /// 그 달 합계가 왜 다른지를 설명하는 게 이 수의 유일한 쓸모다.
    ///
    /// 부호가 방향을 정한다. `amount` 가 음수면 적힌 통장에서 나간 것이고,
    /// 양수면 상대 통장에서 들어온 것이다.
    var internalTransferFlows: [AccountFlow] {
        var sums: [AccountFlow.Direction: Int] = [:]
        for tx in filtered {
            guard let counter = tx.counterAccountId else { continue }
            let direction = tx.amount < 0
                ? AccountFlow.Direction(from: tx.accountId, to: counter)
                : AccountFlow.Direction(from: counter, to: tx.accountId)
            sums[direction, default: 0] += abs(tx.amount)
        }
        return sums
            .map { AccountFlow(direction: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// 이 달이 시작될 때의 총 잔액 (= 월별 보고서의 전월이월).
    ///
    /// 예전에는 `첫거래.balance − 첫거래.amount` 로 구했다. 거래마다 은행이 계산한
    /// 잔액이 박혀 있던 시절의 방법인데, **두 통장을 한 장부에 적으면서 그 칸이
    /// 어느 통장의 잔액도 아니게 되어** 없앴다.
    ///
    /// 지금은 **통장 개시잔액 합 + 그 달 이전의 실제 수입·지출**로 유도한다.
    /// 내부 이체는 더하지 않는다 — 한 통장에서 나가 다른 통장으로 들어가므로
    /// 장부 전체로는 0이고, 더하면 한쪽만 세어 이월액이 틀어진다.
    var openingBalance: Int {
        let opening = accounts.reduce(0) { $0 + $1.openingBalance }
        let before = transactions
            .filter { $0.datetime < startDate && !$0.isInternalTransfer }
            .reduce(0) { $0 + $1.amount }
        return opening + before
    }
}
