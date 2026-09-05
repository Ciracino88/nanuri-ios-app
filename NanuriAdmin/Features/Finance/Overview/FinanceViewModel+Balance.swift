import Foundation

extension FinanceViewModel {

    // MARK: - 잔액은 저장하지 않고 유도한다

    /// 한 통장의 잔액. 개시잔액에서 시작해 그 통장을 지나간 돈을 전부 더한다.
    ///
    /// **내부 이체는 한 항목이 양쪽 통장에 걸친다.** 항목이 적힌 통장(`accountId`)은
    /// 부호 그대로, **상대 통장은 부호를 뒤집어** 더해야 두 통장 잔액이 모두 맞는다.
    /// 상대는 늘 '다른 통장 하나'다(통장 2개 고정) — 이 통장 것이 아니면서 이체인
    /// 항목이면, 이 통장이 그 상대다.
    func balance(of account: Account, asOf date: Date? = nil) -> Int {
        var sum = account.openingBalance
        for item in items {
            if let date, item.datetime > date { continue }
            if item.accountId == account.id {
                sum += item.amount
            } else if item.isInternalTransfer {
                sum -= item.amount
            }
        }
        return sum
    }

    /// 총 재정 = 모든 통장의 잔액 합.
    /// 내부 이체는 한쪽에서 빠지고 다른 쪽에 더해져 **저절로 상쇄된다.**
    func totalBalance(asOf date: Date? = nil) -> Int {
        accounts.reduce(0) { $0 + balance(of: $1, asOf: date) }
    }

    /// 이 달에 **통장 사이를 오간 돈.** 보낸 통장 → 받은 통장 방향별로 합친다.
    ///
    /// 통장 화면만 이걸 본다 — 통장별 잔액과 그 달 합계가 왜 다른지를 설명하는 게
    /// 이 수의 유일한 쓸모다. 부호가 방향을 정한다: 음수면 적힌 통장에서 나간 것,
    /// 양수면 상대 통장에서 들어온 것. 상대는 늘 '다른 통장 하나'다.
    var internalTransferFlows: [AccountFlow] {
        var sums: [AccountFlow.Direction: Int] = [:]
        for item in filtered where item.isInternalTransfer {
            guard let other = accounts.first(where: { $0.id != item.accountId })?.id else { continue }
            let direction = item.amount < 0
                ? AccountFlow.Direction(from: item.accountId, to: other)
                : AccountFlow.Direction(from: other, to: item.accountId)
            sums[direction, default: 0] += abs(item.amount)
        }
        return sums
            .map { AccountFlow(direction: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// 이 달이 시작될 때의 총 잔액 (= 월별 보고서의 전월이월).
    ///
    /// **통장 개시잔액 합 + 그 달 이전의 실제 수입·지출**로 유도한다. 내부 이체는
    /// 더하지 않는다 — 한 통장에서 나가 다른 통장으로 들어가므로 장부 전체로는 0이고,
    /// 더하면 한쪽만 세어 이월액이 틀어진다.
    var openingBalance: Int {
        let opening = accounts.reduce(0) { $0 + $1.openingBalance }
        let before = items
            .filter { $0.datetime < startDate && !$0.isInternalTransfer }
            .reduce(0) { $0 + $1.amount }
        return opening + before
    }
}
