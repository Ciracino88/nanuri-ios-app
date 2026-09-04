import SwiftUI

extension FinanceViewModel {

    /// 보고서용 항목: 분할이 있으면 분할들, 없으면 거래 자체.
    /// **내부 이체는 여기 안 들어온다** (`filteredExternal`).
    var reportItems: [ReportLineItem] {
        filteredExternal.flatMap { tx -> [ReportLineItem] in
            let splits = splits(for: tx.id)
            guard !splits.isEmpty else {
                // **손으로 넣은 거래의 적요는 사람이 쓴 값이다.** 그래서 분할 조각과
                // 같은 자리(`lineDescription`)에 놓아 이름으로도 쓰이고 같은 날 같은
                // 적요끼리 합쳐지기도 한다 — ATM 에서 세 번 나눠 뽑은 18만원이
                // 장부에서 한 줄이 되는 게 그것이다.
                //
                // 거래내역서에서 온 거래는 다르다. 그 적요는 은행이 준 값
                // (`이충성`·`우성볼링장`)이라 줄마다 달라서, 이름으로 쓰면 묶음이
                // 통째로 무너진다. `sourceDescription` 에만 둔다.
                let written = tx.source == .manual ? tx.description : nil
                return [ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                                       magnitude: abs(tx.amount), category: tx.category,
                                       lineDescription: written, sourceDescription: tx.description)]
            }
            return splits.map {
                ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                               magnitude: $0.amount, category: $0.category,
                               lineDescription: $0.description, sourceDescription: tx.description)
            }
        }
    }

    /// 지금까지 입력된 카테고리를 사용 빈도순으로 반환 (편집 시 추천용). 분할 카테고리도 포함.
    var usedCategories: [String] {
        var all = transactions
            .compactMap { $0.category?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        all += splitsByTransaction.values.flatMap { $0 }
            .compactMap { $0.category?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let counts = Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
        return counts.keys.sorted { counts[$0]! > counts[$1]! }
    }

    var totalDeposit: Int { deposits.reduce(0) { $0 + $1.amount } }

    var totalWithdrawal: Int { withdrawals.reduce(0) { $0 + abs($1.amount) } }

    // MARK: - 요약이 쓰는 값들

    /// 지난달 총 출금. **비교할 지난달이 아예 없으면 `nil`** 이다.
    ///
    /// 0 을 돌려주면 "지난달보다 전부 더 썼다" 는 문장이 나오는데, 그건 지난달에
    /// 안 쓴 게 아니라 **장부가 그때부터 시작하지 않았다**는 뜻일 수 있다.
    /// 둘을 구분해야 해서 `Optional` 이다.
    var previousMonthWithdrawal: Int? {
        let cal = Calendar.current
        guard let previous = cal.date(byAdding: .month, value: -1, to: currentMonth) else { return nil }
        let start = cal.startOfMonth(previous)
        let end = cal.endOfMonth(previous)
        let items = transactions.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !items.isEmpty else { return nil }
        return items.reduce(0) { $0 + abs($1.amount) }
    }

    /// 지난달과 견준 한 문장·색. 요약 밴드와 분석 화면이 이걸 같이 쓴다.
    var comparison: SpendingComparison {
        SpendingComparison(previousWithdrawal: previousMonthWithdrawal,
                           totalWithdrawal: totalWithdrawal,
                           totalDeposit: totalDeposit)
    }

    /// 이 달 출금(또는 입금)을 카테고리로 묶어 **큰 것부터** 돌려준다.
    ///
    /// `reportItems` 로 센다 — 한 거래를 여러 항목으로 쪼갠 분할 거래는 조각마다
    /// 카테고리가 다르므로, **거래 단위로 세면 통째로 첫 조각의 카테고리에 들어간다.**
    /// 묶는 이름은 `ReportLineItem.categoryLabel` 이 정해서 보고서와 같은 규칙을 탄다.
    ///
    /// 금액이 같으면 이름순이다. 순서가 매번 흔들리면 같은 달을 다시 열었을 때
    /// 막대의 색이 자리를 바꾼다.
    func categoryTotals(deposit: Bool) -> [CategoryTotal] {
        var sums: [String: Int] = [:]
        for item in reportItems where item.isDeposit == deposit {
            sums[item.categoryLabel, default: 0] += item.magnitude
        }
        return sums
            .map { CategoryTotal(name: $0.key, amount: $0.value) }
            .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    /// 달 시작부터 하루씩 쌓은 **누적 출금**. 그래프가 쓴다.
    ///
    /// `monthsAgo: 0` 이 이 달, `1` 이 지난달이다. 그 달에 거래가 없으면 빈 배열이라
    /// 그래프가 선을 안 그린다.
    func cumulativeWithdrawals(monthsAgo: Int) -> [Int] {
        let cal = Calendar.current
        guard let month = cal.date(byAdding: .month, value: -monthsAgo, to: currentMonth) else { return [] }
        let start = cal.startOfMonth(month)
        let end = cal.endOfMonth(month)
        let items = transactions.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !items.isEmpty else { return [] }

        var perDay: [Int: Int] = [:]
        for tx in items {
            let day = cal.component(.day, from: tx.datetime)
            perDay[day, default: 0] += abs(tx.amount)
        }
        let dayCount = cal.component(.day, from: end)
        var running = 0
        return (1...dayCount).map { day in
            running += perDay[day] ?? 0
            return running
        }
    }

    /// 날짜별 순증감 (입금 − 출금). 거래가 없는 날은 키가 없다.
    var dailyNet: [Date: Int] {
        let cal = Calendar.current
        var result: [Date: Int] = [:]
        for tx in filteredExternal {
            let day = cal.startOfDay(for: tx.datetime)
            result[day, default: 0] += tx.isDeposit ? tx.amount : -abs(tx.amount)
        }
        return result
    }
}
