import SwiftUI

extension FinanceViewModel {

    /// 보고서용 항목. **내부 이체는 여기 안 들어온다** (`filteredExternal`).
    ///
    /// 항목이 곧 장부 줄이라 그대로 옮긴다 — `lineDescription` 은 항목의 적요(사람 값),
    /// `sourceDescription` 은 그 항목이 나온 은행 거래의 적요다(농협 항목은 없음).
    var reportItems: [ReportLineItem] {
        filteredExternal.map { item in
            ReportLineItem(datetime: item.datetime,
                           isDeposit: item.isDeposit,
                           magnitude: abs(item.amount),
                           category: item.category,
                           lineDescription: item.description,
                           sourceDescription: transaction(for: item)?.description)
        }
    }

    /// 지금까지 입력된 카테고리를 사용 빈도순으로 반환 (편집 시 추천용).
    var usedCategories: [String] {
        categoryUsage.map(\.name)
    }

    /// 카테고리별 **이름 + 쓰인 항목 수**를 많이 쓴 것부터 돌려준다.
    ///
    /// 아이콘 관리 화면이 "자주 쓴 카테고리" 를 이 순서로 보여주고, `usedCategories`
    /// 추천 칩도 여기서 이름만 뽑아 쓴다. **온 기간을 다 센다** — 아이콘은 이 달만의
    /// 취향이 아니라 그 카테고리 전체에 붙는 것이라, 달 필터를 타면 안 된다.
    var categoryUsage: [(name: String, count: Int)] {
        let all = items
            .compactMap { $0.category?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let counts = Dictionary(grouping: all, by: { $0 }).mapValues(\.count)
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var totalDeposit: Int { deposits.reduce(0) { $0 + $1.amount } }
    var totalWithdrawal: Int { withdrawals.reduce(0) { $0 + abs($1.amount) } }

    // MARK: - 요약이 쓰는 값들

    /// 지난달 총 출금. **비교할 지난달이 아예 없으면 `nil`** 이다.
    var previousMonthWithdrawal: Int? {
        let cal = Calendar.current
        guard let previous = cal.date(byAdding: .month, value: -1, to: currentMonth) else { return nil }
        let start = cal.startOfMonth(previous)
        let end = cal.endOfMonth(previous)
        let rows = items.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !rows.isEmpty else { return nil }
        return rows.reduce(0) { $0 + abs($1.amount) }
    }

    /// 지난달과 견준 한 문장·색. 요약 밴드와 분석 화면이 이걸 같이 쓴다.
    var comparison: SpendingComparison {
        SpendingComparison(previousWithdrawal: previousMonthWithdrawal,
                           totalWithdrawal: totalWithdrawal,
                           totalDeposit: totalDeposit)
    }

    /// 이 달 출금(또는 입금)을 카테고리로 묶어 **큰 것부터** 돌려준다.
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
    func cumulativeWithdrawals(monthsAgo: Int) -> [Int] {
        let cal = Calendar.current
        guard let month = cal.date(byAdding: .month, value: -monthsAgo, to: currentMonth) else { return [] }
        let start = cal.startOfMonth(month)
        let end = cal.endOfMonth(month)
        let rows = items.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !rows.isEmpty else { return [] }

        var perDay: [Int: Int] = [:]
        for item in rows {
            let day = cal.component(.day, from: item.datetime)
            perDay[day, default: 0] += abs(item.amount)
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
        for item in filteredExternal {
            let day = cal.startOfDay(for: item.datetime)
            result[day, default: 0] += item.isDeposit ? item.amount : -abs(item.amount)
        }
        return result
    }
}
