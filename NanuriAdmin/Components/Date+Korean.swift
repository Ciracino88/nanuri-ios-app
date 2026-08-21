import Foundation

/// 기기 언어와 무관하게 항상 한국어 형식으로 날짜를 표시하기 위한 헬퍼.
extension Date {
    private static func koreanFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = format
        return f
    }

    private static let koreanDate = koreanFormatter("yyyy년 M월 d일")
    private static let koreanShortDate = koreanFormatter("M월 d일")
    private static let koreanDateTime = koreanFormatter("yyyy년 M월 d일 a h:mm")
    private static let koreanTime = koreanFormatter("a h:mm")
    private static let koreanYearMonth = koreanFormatter("yyyy년 M월")

    /// 2026년 7월
    var koreanYearMonthString: String { Date.koreanYearMonth.string(from: self) }
    /// 2026년 7월 4일
    var koreanDateString: String { Date.koreanDate.string(from: self) }
    /// 7월 4일
    var koreanShortDateString: String { Date.koreanShortDate.string(from: self) }
    /// 2026년 7월 4일 오후 4:41
    var koreanDateTimeString: String { Date.koreanDateTime.string(from: self) }
    /// 오후 4:41
    var koreanTimeString: String { Date.koreanTime.string(from: self) }
}

extension Date {
    private static let koreanDayHeader = koreanFormatter("M월 d일 E")

    /// 7월 28일 화 — 날짜별로 묶은 카드의 머리.
    ///
    /// **요일에 괄호를 두르지 않는다.** 참조 시스템의 날짜 표기 규칙이다.
    var koreanDayHeaderString: String { Date.koreanDayHeader.string(from: self) }
}

extension Date {
    private static let koreanDaySection = koreanFormatter("d일 EEEE")

    /// 28일 화요일 — 하루치 섹션의 머리.
    ///
    /// 달은 적지 않는다. 화면 전체가 이미 한 달이라 매 섹션마다 되풀이할 이유가 없다.
    var koreanDaySectionString: String { Date.koreanDaySection.string(from: self) }
}

extension Date {
    private static let koreanWeekday = koreanFormatter("E")
    private static let koreanDayNumber = koreanFormatter("d")

    /// 화 — 날짜 셀렉터의 요일 칸.
    var koreanWeekdayString: String { Date.koreanWeekday.string(from: self) }
    /// 28 — 날짜 셀렉터의 날짜 칸.
    var koreanDayNumberString: String { Date.koreanDayNumber.string(from: self) }
}
