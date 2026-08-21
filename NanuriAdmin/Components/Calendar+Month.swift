import Foundation

/// 달 단위로 자르는 계산.
///
/// 재정 탭이 장부를 **한 달씩** 보여준다 (`FinanceViewModel.currentMonth`).
/// 달의 경계를 화면 코드에서 매번 계산하면 한쪽만 틀리기 쉬워서 여기 모아 둔다.
extension Calendar {
    /// 그 날이 속한 달의 1일 0시.
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    /// 그 날이 속한 달의 **마지막 순간** (말일 23:59:59).
    ///
    /// 다음 달 1일 0시에서 1초를 뺀다. 말일을 28·30·31 중 무엇으로 볼지 따지지
    /// 않아도 되고, 윤달·서머타임에도 달력이 알아서 맞춘다.
    func endOfMonth(_ date: Date) -> Date {
        let start = startOfMonth(date)
        guard let next = self.date(byAdding: .month, value: 1, to: start) else { return start }
        return next.addingTimeInterval(-1)
    }
}
