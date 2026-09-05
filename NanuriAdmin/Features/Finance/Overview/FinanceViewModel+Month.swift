import Foundation

extension FinanceViewModel {

    // MARK: - 달 넘기기

    /// 넘겨 볼 수 있는 달들 (과거 → 현재). 거래가 한 건도 없는 중간 달도 포함한다 —
    /// 장부는 비어 있어도 그 달이 존재하고, 건너뛰면 이어지는 느낌이 끊긴다.
    ///
    /// 뒤쪽 끝은 **마지막 거래가 있는 달과 이번 달 중 나중**이다. 이번 달에 아직
    /// 거래가 없어도 열 수 있어야 하기 때문이다 (오늘 넣은 게 여기 뜬다).
    var selectableMonths: [Date] {
        let cal = Calendar.current
        let months = items.map { cal.startOfMonth($0.datetime) }
        let thisMonth = cal.startOfMonth(Date())
        guard var cursor = months.min() else { return [thisMonth] }
        let last = max(months.max() ?? thisMonth, thisMonth)

        var result: [Date] = []
        while cursor <= last {
            result.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// 그 달에 거래가 있는지 (달 고르는 메뉴에서 빈 달을 흐리게 보여주려고).
    func hasTransactions(in month: Date) -> Bool {
        let cal = Calendar.current
        return items.contains { cal.isDate($0.datetime, equalTo: month, toGranularity: .month) }
    }

    var canGoToPreviousMonth: Bool {
        guard let first = selectableMonths.first else { return false }
        return currentMonth > first
    }

    var canGoToNextMonth: Bool {
        guard let last = selectableMonths.last else { return false }
        return currentMonth < last
    }

    func goToPreviousMonth() {
        guard canGoToPreviousMonth,
              let previous = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        currentMonth = previous
    }

    func goToNextMonth() {
        guard canGoToNextMonth,
              let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) else { return }
        currentMonth = next
    }

    /// 거래를 받아온 직후, 자료가 있는 **마지막 달**로 한 번만 데려간다.
    /// 이게 없으면 이관 직후처럼 과거 자료만 있을 때 빈 이번 달이 열려 "아무것도
    /// 없다"로 보인다. 사용자가 달을 넘긴 뒤에는 다시 건드리지 않는다.
    func positionAtLatestMonthIfNeeded() {
        guard needsInitialMonth else { return }
        needsInitialMonth = false
        let cal = Calendar.current
        if let latest = items.map({ cal.startOfMonth($0.datetime) }).max() {
            currentMonth = latest
        }
    }

    /// 이 달에 있는 날들 (1일 → 말일). 날짜 셀렉터가 훑는 축이다.
    ///
    /// 거래가 없는 날도 뺀 자리를 남긴다 — 건너뛰면 날짜 간격이 들쭉날쭉해져서
    /// 어느 날이 비었는지가 안 보인다.
    var daysInCurrentMonth: [Date] {
        let cal = Calendar.current
        var days: [Date] = []
        var cursor = cal.startOfDay(for: startDate)
        let last = cal.startOfDay(for: endDate)
        while cursor <= last {
            days.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// 이 달을 덮는 주들 (일요일 시작). 날짜 셀렉터가 한 주씩 넘긴다.
    ///
    /// 달 경계에 걸친 주는 **이전·다음 달 날짜까지 그대로 들고 온다** — 한 주는
    /// 일곱 칸이어야 요일 자리가 안 흔들린다. 그 칸들은 이 달 밖이라 눌리지 않는다.
    var weeksInCurrentMonth: [[Date]] {
        var cal = Calendar.current
        cal.firstWeekday = 1  // 일요일 시작
        let days = daysInCurrentMonth
        guard let first = days.first, let last = days.last else { return [] }
        guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: first) else { return [] }

        var weeks: [[Date]] = []
        var cursor = cal.startOfDay(for: firstWeek.start)
        while cursor <= last {
            var week: [Date] = []
            for offset in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: cursor) else { break }
                week.append(cal.startOfDay(for: day))
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// 그 날이 지금 보고 있는 달에 속하는가. 주 단위로 끊다 보면 앞뒤 달이 섞인다.
    func isInCurrentMonth(_ day: Date) -> Bool {
        day >= Calendar.current.startOfDay(for: startDate) && day <= endDate
    }
}
