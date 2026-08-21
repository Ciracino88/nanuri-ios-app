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
