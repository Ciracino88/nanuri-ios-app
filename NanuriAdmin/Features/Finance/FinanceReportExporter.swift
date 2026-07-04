import UIKit

/// 재정 보고서(PDF)와 영수증 부록(PDF)을 생성한다.
enum FinanceReportExporter {

    // MARK: - 공용

    private static let wonFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    private static func won(_ n: Int) -> String {
        (wonFormatter.string(from: NSNumber(value: n)) ?? "\(n)") + "원"
    }

    /// 콤마 구분 숫자 (원 단위 표기 없이). 보고서 표에서 사용.
    private static func num(_ n: Int) -> String {
        wonFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// A4 (pt)
    private static let pageSize = CGSize(width: 595.2, height: 841.8)

    private static func categoryKey(_ category: String?) -> String {
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return "미분류"
    }

    /// 카테고리별 합계 (금액 큰 순). 카테고리 없으면 "미분류".
    private static func categoryTotals(_ items: [ReportLineItem]) -> [(String, Int)] {
        var order: [String] = []
        var sums: [String: Int] = [:]
        for it in items {
            let key = categoryKey(it.category)
            if sums[key] == nil { order.append(key) }
            sums[key, default: 0] += it.magnitude
        }
        return order.map { ($0, sums[$0]!) }.sorted { $0.1 > $1.1 }
    }

    // MARK: - 재정 보고서 PDF (모드별, 영수증 미포함)

    static func makeReportPDF(mode: FinanceReportMode, items: [ReportLineItem], opening: Int, startDate: Date, endDate: Date, ledgerName: String) -> URL? {
        let html: String
        let safeName = sanitizeFilename(ledgerName)
        switch mode {
        case .monthly:
            html = buildMonthlyHTML(items: items, opening: opening, startDate: startDate, endDate: endDate)
        case .event:
            html = buildEventHTML(items: items, startDate: startDate, endDate: endDate, eventName: ledgerName)
        }
        return renderHTMLToPDF(html, filename: "\(safeName)_\(rangeSuffix(startDate, endDate)).pdf")
    }

    /// 파일명에 쓸 수 없는 문자를 제거한다.
    private static func sanitizeFilename(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "재정보고서" : cleaned
    }

    private static func renderHTMLToPDF(_ html: String, filename: String) -> URL? {

        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)

        let pageRect = CGRect(origin: .zero, size: pageSize)
        let printable = pageRect.insetBy(dx: 28, dy: 28)
        renderer.setValue(NSValue(cgRect: pageRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, pageRect, nil)
        let pages = renderer.numberOfPages
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        let bounds = UIGraphicsGetPDFContextBounds()
        for i in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: bounds)
        }
        UIGraphicsEndPDFContext()

        return write(data as Data, filename: filename)
    }

    // MARK: - 월별 회계 보고서 (전월이월 → 누적 잔액)

    private static func buildMonthlyHTML(items: [ReportLineItem], opening: Int, startDate: Date, endDate: Date) -> String {
        let cal = Calendar.current
        let sorted = items.sorted { $0.datetime < $1.datetime }

        let deposits = sorted.filter { $0.isDeposit }
        let withdrawals = sorted.filter { !$0.isDeposit }
        let totalIncome = opening + deposits.reduce(0) { $0 + $1.magnitude }
        let totalExpense = withdrawals.reduce(0) { $0 + $1.magnitude }
        let ending = totalIncome - totalExpense   // = 전월이월 + 순수지

        // 제목: 같은 달이면 "YYYY년 M월", 아니면 기간 범위
        let titleFmt = DateFormatter()
        titleFmt.locale = Locale(identifier: "ko_KR")
        let title: String
        if cal.isDate(startDate, equalTo: endDate, toGranularity: .month) {
            titleFmt.dateFormat = "yyyy년 M월"
            title = titleFmt.string(from: startDate)
        } else {
            titleFmt.dateFormat = "yyyy년 M월 d일"
            title = "\(titleFmt.string(from: startDate)) ~ \(titleFmt.string(from: endDate))"
        }

        // --- 상세 명세 (월 / 일 / 적요 / 수입 / 지출 / 잔액) ---
        // 같은 날짜 + 같은 카테고리 + 같은 입출금 방향은 한 줄로 합산한다 (적요 = 카테고리).
        // 카테고리가 없는 항목은 합치지 않고 거래 내용으로 개별 표시한다.
        var rows: [(label: String, isDeposit: Bool, amount: Int, day: Date)] = []
        var indexByKey: [String: Int] = [:]
        for it in sorted {
            let day = cal.startOfDay(for: it.datetime)
            let category = it.category?.trimmingCharacters(in: .whitespaces) ?? ""
            if category.isEmpty {
                let desc = it.sourceDescription?.trimmingCharacters(in: .whitespaces) ?? ""
                rows.append((desc.isEmpty ? "미분류" : desc, it.isDeposit, it.magnitude, day))
            } else {
                let key = "\(day.timeIntervalSince1970)|\(category)|\(it.isDeposit)"
                if let idx = indexByKey[key] {
                    rows[idx].amount += it.magnitude
                } else {
                    indexByKey[key] = rows.count
                    rows.append((category, it.isDeposit, it.magnitude, day))
                }
            }
        }

        let openMonth = cal.component(.month, from: sorted.first?.datetime ?? startDate)
        var detail = """
        <tr><td>\(openMonth)</td><td>1</td><td>전월이월</td>\
        <td class='num'>\(num(opening))</td><td></td><td class='num'>\(num(opening))</td></tr>
        """
        var running = opening
        var lastMonth = openMonth
        var lastDay = 1
        for row in rows {
            let m = cal.component(.month, from: row.day)
            let d = cal.component(.day, from: row.day)
            let monthCell = (m != lastMonth) ? "\(m)" : ""
            let dayCell = (m != lastMonth || d != lastDay) ? "\(d)" : ""
            lastMonth = m
            lastDay = d
            running += row.isDeposit ? row.amount : -row.amount
            let income = row.isDeposit ? num(row.amount) : ""
            let expense = row.isDeposit ? "" : num(row.amount)
            detail += """
            <tr><td>\(monthCell)</td><td>\(dayCell)</td><td class='desc'>\(htmlEscape(row.label))</td>\
            <td class='num'>\(income)</td><td class='num'>\(expense)</td><td class='num'>\(num(running))</td></tr>
            """
        }

        // --- 요약 (수입 / 지출 대응) ---
        let incomeLines: [(String, Int)] = [("전월이월", opening)] + categoryTotals(deposits)
        let expenseLines: [(String, Int)] = categoryTotals(withdrawals)
        var summary = ""
        for i in 0..<max(incomeLines.count, expenseLines.count) {
            let il = i < incomeLines.count ? htmlEscape(incomeLines[i].0) : ""
            let ia = i < incomeLines.count ? num(incomeLines[i].1) : ""
            let el = i < expenseLines.count ? htmlEscape(expenseLines[i].0) : ""
            let ea = i < expenseLines.count ? num(expenseLines[i].1) : ""
            summary += "<tr><td>\(il)</td><td class='num'>\(ia)</td><td>\(el)</td><td class='num'>\(ea)</td></tr>"
        }
        summary += "<tr class='total'><td>합계</td><td class='num'>\(num(totalIncome))</td><td>합계</td><td class='num'>\(num(totalExpense))</td></tr>"
        summary += "<tr class='total'><td></td><td></td><td>잔액</td><td class='num'>\(num(ending))</td></tr>"

        return """
        <html><head><meta charset='utf-8'><style>
        * { -webkit-print-color-adjust: exact; }
        body { font-family: -apple-system, 'Apple SD Gothic Neo', sans-serif; color:#111; font-size:12px; }
        h1 { font-size:18px; text-align:center; margin:0 0 12px; }
        table { width:100%; border-collapse:collapse; margin-bottom:24px; }
        th,td { border:1px solid #333; padding:5px 8px; text-align:center; }
        td.num { text-align:right; font-variant-numeric: tabular-nums; }
        td.desc { text-align:center; }
        thead th { background:#f2f2f2; font-weight:600; }
        tr.total td { font-weight:700; background:#fafafa; }
        .section-title { font-size:13px; font-weight:700; margin:18px 0 6px; }
        </style></head><body>
        <h1>\(title)</h1>

        <table>
          <thead><tr><th>월</th><th>일</th><th>적요</th><th>수입</th><th>지출</th><th>잔액</th></tr></thead>
          <tbody>\(detail)</tbody>
        </table>

        <div class='section-title'>수입 · 지출 요약</div>
        <table>
          <thead><tr><th colspan='2'>수입</th><th colspan='2'>지출</th></tr></thead>
          <tbody>\(summary)</tbody>
        </table>
        </body></html>
        """
    }

    // MARK: - 행사 결산 내역 (수입/지출 좌우 대응, 항목별 개별 나열, 전월이월·누적 잔액 없음)

    private static func buildEventHTML(items: [ReportLineItem], startDate: Date, endDate: Date, eventName: String?) -> String {
        let deposits = items.filter { $0.isDeposit }
        let withdrawals = items.filter { !$0.isDeposit }
        let totalIncome = deposits.reduce(0) { $0 + $1.magnitude }
        let totalExpense = withdrawals.reduce(0) { $0 + $1.magnitude }
        let net = totalIncome - totalExpense

        // 카테고리(항목)별로 묶되 합산하지 않고 개별 항목을 나열한다.
        // 항목명은 그룹 첫 줄에만 표시(이후 공백), 내용 = 메모.
        func displayRows(_ its: [ReportLineItem]) -> [(item: String, amount: String, note: String)] {
            var order: [String] = []
            var groups: [String: [ReportLineItem]] = [:]
            for it in its.sorted(by: { $0.datetime < $1.datetime }) {
                let key = categoryKey(it.category)
                if groups[key] == nil { order.append(key); groups[key] = [] }
                groups[key]?.append(it)
            }
            var result: [(String, String, String)] = []
            for cat in order {
                for (i, it) in (groups[cat] ?? []).enumerated() {
                    let note = it.memo?.trimmingCharacters(in: .whitespaces) ?? ""
                    result.append((i == 0 ? cat : "", num(it.magnitude), note))
                }
            }
            return result.map { (item: $0.0, amount: $0.1, note: $0.2) }
        }

        let incomeRows = displayRows(deposits)
        let expenseRows = displayRows(withdrawals)
        let rowCount = max(incomeRows.count, expenseRows.count)

        var body = ""
        for i in 0..<rowCount {
            let inc = i < incomeRows.count ? incomeRows[i] : (item: "", amount: "", note: "")
            let exp = i < expenseRows.count ? expenseRows[i] : (item: "", amount: "", note: "")
            body += """
            <tr>\
            <td>\(htmlEscape(inc.item))</td><td class='num'>\(inc.amount)</td><td>\(htmlEscape(inc.note))</td>\
            <td>\(htmlEscape(exp.item))</td><td class='num'>\(exp.amount)</td><td>\(htmlEscape(exp.note))</td>\
            </tr>
            """
        }
        // 총계 (양측) + 잔액 (수입측)
        body += """
        <tr class='total'><td>총계</td><td class='num'>\(num(totalIncome))</td><td></td>\
        <td>총계</td><td class='num'>\(num(totalExpense))</td><td></td></tr>
        <tr class='total'><td>잔액</td><td class='num'>\(num(net))</td><td></td><td></td><td></td><td></td></tr>
        """

        let dateFmt = DateFormatter()
        dateFmt.locale = Locale(identifier: "ko_KR")
        dateFmt.dateFormat = "yyyy년 M월 d일"
        let title = (eventName?.isEmpty == false) ? eventName! : "행사 결산 내역"

        return """
        <html><head><meta charset='utf-8'><style>
        * { -webkit-print-color-adjust: exact; }
        body { font-family: -apple-system, 'Apple SD Gothic Neo', sans-serif; color:#111; font-size:12px; }
        h1 { font-size:18px; text-align:center; margin:0 0 4px; }
        .sub { text-align:center; color:#666; font-size:11px; margin-bottom:16px; }
        table { width:100%; border-collapse:collapse; }
        th,td { border:1px solid #333; padding:5px 8px; text-align:left; }
        td.num, th.num { text-align:right; font-variant-numeric: tabular-nums; }
        thead th { background:#f2f2f2; font-weight:600; text-align:center; }
        tr.total td { font-weight:700; background:#fafafa; }
        </style></head><body>
        <h1>\(title)</h1>
        <div class='sub'>기간: \(dateFmt.string(from: startDate)) ~ \(dateFmt.string(from: endDate))</div>
        <table>
          <thead>
            <tr><th colspan='3'>수입</th><th colspan='3'>지출</th></tr>
            <tr><th>항목</th><th class='num'>금액</th><th>내용</th><th>항목</th><th class='num'>금액</th><th>내용</th></tr>
          </thead>
          <tbody>\(body)</tbody>
        </table>
        </body></html>
        """
    }

    // MARK: - 영수증 부록 PDF

    static func makeReceiptsPDF(transactions: [BankTransaction], startDate: Date, endDate: Date) async -> URL? {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        // (라벨, 이미지 URL) 목록 구성
        struct Entry { let label: String; let url: String }
        var entries: [Entry] = []
        for tx in transactions.sorted(by: { $0.datetime < $1.datetime }) {
            let receipts = tx.receipts
            for (i, urlString) in receipts.enumerated() {
                var label = "\(dateFmt.string(from: tx.datetime)) · \(tx.description ?? "-") · \(won(abs(tx.amount)))"
                if let cat = tx.category, !cat.isEmpty { label += " · \(cat)" }
                if receipts.count > 1 { label += " (\(i + 1)/\(receipts.count))" }
                entries.append(Entry(label: label, url: urlString))
            }
        }
        guard !entries.isEmpty else { return nil }

        // 이미지 다운로드
        var pages: [(label: String, image: UIImage)] = []
        for entry in entries {
            guard let url = URL(string: entry.url),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { continue }
            pages.append((entry.label, image))
        }
        guard !pages.isEmpty else { return nil }

        // 렌더링 (한 페이지에 영수증 한 장 + 상단 라벨)
        let pageRect = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("재정영수증부록_\(rangeSuffix(startDate, endDate)).pdf")

        do {
            try renderer.writePDF(to: url) { ctx in
                let margin: CGFloat = 28
                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
                for page in pages {
                    ctx.beginPage()
                    let labelRect = CGRect(x: margin, y: margin,
                                           width: pageSize.width - margin * 2, height: 40)
                    (page.label as NSString).draw(in: labelRect, withAttributes: labelAttrs)

                    let imgTop = margin + 44
                    let available = CGRect(x: margin, y: imgTop,
                                           width: pageSize.width - margin * 2,
                                           height: pageSize.height - imgTop - margin)
                    page.image.draw(in: aspectFitRect(imageSize: page.image.size, in: available))
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 헬퍼

    private static func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.minY, width: w, height: h)
    }

    private static func rangeSuffix(_ start: Date, _ end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "\(f.string(from: start))_\(f.string(from: end))"
    }

    private static func write(_ data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
