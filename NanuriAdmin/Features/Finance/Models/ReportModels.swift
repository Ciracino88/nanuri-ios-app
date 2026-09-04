import Foundation

/// 보고서 한 줄을 구성하는 항목. 거래 자체이거나, 분할된 조각이다.
/// (통장 거래와 보고서 항목의 입도 차이를 흡수하는 중간 표현)
struct ReportLineItem {
    let datetime: Date
    let isDeposit: Bool
    let magnitude: Int          // 항상 양수
    let category: String?
    /// **이 줄이 스스로 갖는 적요.** 분할 조각만 갖는다.
    ///
    /// 거래 자체는 여기가 `nil` 이다 — 거래의 적요는 은행이 준 값이라
    /// `sourceDescription` 에 있고, 성격이 다르다. 아래 `reportLabel` 참고.
    let lineDescription: String?
    /// 이 줄이 나온 거래의 적요. 분할 조각이면 **부모 거래의** 것이다.
    let sourceDescription: String?

    /// 묶을 때 쓰는 카테고리 이름. 비어 있으면 **"미지정"** 이다.
    ///
    /// 보고서(`FinanceReportExporter`)와 분석 화면(`SpendingDetailView`)이 같은
    /// 이름으로 묶어야 두 곳의 합계가 어긋나지 않는다. 빈 카테고리를 버리지 않고
    /// 한 덩어리로 모으는 것도 그래서다 — 카테고리가 덜 붙은 달일수록 그 덩어리가 커야
    /// "아직 안 나눴다" 는 게 보인다.
    var categoryLabel: String {
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return "미지정"
    }

    /// 보고서 상세 명세의 **적요 칸에 찍히는 이름.** `적요 → 카테고리 → 거래 적요` 순이다.
    ///
    /// 적요가 먼저인데 **그 적요는 분할 조각만 갖는다.** 거래의 적요(은행이 준 값)를
    /// 여기 끌어오지 않는 건 의도다 — 그 값은 줄마다 다르므로 이름으로 쓰면
    /// "같은 날 · 같은 카테고리는 한 줄" 이라는 엑셀식 묶음이 통째로 무너진다.
    /// 분할 조각의 적요는 사람이 **그 줄을 위해** 적은 값이라 그렇지 않다.
    var reportLabel: String {
        if let d = lineDescription?.trimmingCharacters(in: .whitespaces), !d.isEmpty { return d }
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let s = sourceDescription?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s }
        return "미지정"
    }

    /// 같은 날 · 같은 방향의 다른 줄과 합쳐도 되는가.
    ///
    /// **사람이 이름을 준 줄만 합친다.** 적요도 카테고리도 없어서 은행이 준 적요로
    /// 떨어진 줄은 합치지 않는다 — 그 이름은 우연히 같을 수 있고, 합치면 아직
    /// 카테고리가 안 붙은 항목이 한 덩어리로 뭉쳐 "안 나눴다" 는 게 안 보인다.
    var mergesInReport: Bool {
        let d = lineDescription?.trimmingCharacters(in: .whitespaces) ?? ""
        let c = category?.trimmingCharacters(in: .whitespaces) ?? ""
        return !d.isEmpty || !c.isEmpty
    }
}

/// 카테고리 하나에 묶인 합계. 분석 화면의 막대와 목록이 같이 쓴다.
struct CategoryTotal: Identifiable {
    let name: String
    let amount: Int

    var id: String { name }
}
