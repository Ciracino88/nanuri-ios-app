import Foundation

extension FinanceViewModel {

    // MARK: - 내보내기

    /// 화면(웹뷰)에 띄울 보고서 HTML. PDF와 같은 표를 같은 코드로 만든다.
    func reportHTML() -> String? {
        FinanceReportExporter.makeReportHTML(
            items: reportItems, opening: openingBalance,
            startDate: startDate, endDate: endDate, forScreen: true
        )
    }

    /// 현재 기간의 거래내역을 PDF 보고서로 만든다 (영수증 미포함).
    func exportReportPDF() -> URL? {
        guard let url = FinanceReportExporter.makeReportPDF(
            items: reportItems, opening: openingBalance,
            startDate: startDate, endDate: endDate, ledgerName: "나누리 회계"
        ) else {
            error = "보고서 생성에 실패했어요."
            return nil
        }
        return url
    }

    /// 현재 기간의 영수증 이미지를 모은 부록 PDF를 만든다. **항목의 영수증**을 모은다.
    func exportReceiptsPDF() async -> URL? {
        guard let url = await FinanceReportExporter.makeReceiptsPDF(
            items: filtered, startDate: startDate, endDate: endDate
        ) else {
            error = "이 기간에 첨부된 영수증이 없거나 내보내기에 실패했어요."
            return nil
        }
        return url
    }
}
