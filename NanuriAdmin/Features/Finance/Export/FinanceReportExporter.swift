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

    /// 카테고리별 합계 (금액 큰 순). 카테고리 없으면 "미지정".
    ///
    /// 묶는 이름은 `ReportLineItem.categoryLabel` 이 정한다 — 분석 화면과 같은
    /// 규칙이라야 두 곳의 합계가 어긋나지 않는다.
    private static func categoryTotals(_ items: [ReportLineItem]) -> [(String, Int)] {
        var order: [String] = []
        var sums: [String: Int] = [:]
        for it in items {
            let key = it.categoryLabel
            if sums[key] == nil { order.append(key) }
            sums[key, default: 0] += it.magnitude
        }
        return order.map { ($0, sums[$0]!) }.sorted { $0.1 > $1.1 }
    }

    // MARK: - 재정 보고서 PDF (영수증 미포함)

    /// 보고서 HTML. 화면(웹뷰)과 PDF가 **같은 표를 쓰도록** 하는 단일 진입점이다.
    /// `forScreen` 은 화면 전용 CSS만 얹는다 — 표 내용과 인쇄 결과는 달라지지 않는다.
    static func makeReportHTML(items: [ReportLineItem], opening: Int, startDate: Date, endDate: Date, forScreen: Bool) -> String {
        buildMonthlyHTML(items: items, opening: opening, startDate: startDate, endDate: endDate, forScreen: forScreen)
    }

    /// `ledgerName` 은 표에 안 들어가고 **파일 이름에만** 쓰인다.
    static func makeReportPDF(items: [ReportLineItem], opening: Int, startDate: Date, endDate: Date, ledgerName: String) -> URL? {
        let html = makeReportHTML(items: items, opening: opening,
                                  startDate: startDate, endDate: endDate,
                                  forScreen: false)
        let safeName = sanitizeFilename(ledgerName)
        return renderHTMLToPDF(html, filename: "\(safeName)_\(rangeSuffix(startDate, endDate)).pdf")
    }

    /// 표를 감싸는 가로 스크롤 상자. 화면에서만 두른다 —
    /// 이 둘이 빈 문자열이라 **PDF 로 가는 HTML 은 이전과 한 글자도 다르지 않다.**
    private static func twOpen(_ forScreen: Bool) -> String { forScreen ? "<div class='tw'>" : "" }
    private static func twClose(_ forScreen: Bool) -> String { forScreen ? "</div>" : "" }

    /// 화면에서만 필요한 것 — 기기 폭에 맞추기, 넓은 표는 가로 스크롤, 다크 모드.
    /// PDF 경로에서는 빈 문자열이라 A4 출력이 그대로 유지된다.
    /// (`DESIGN.md` 5번: 보고서는 DS 규칙 밖이라 여기서 색을 직접 적는다)
    private static func screenCSS(_ forScreen: Bool) -> String {
        guard forScreen else { return "" }
        return """
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <style>
        body { margin:0; padding:16px 12px 32px; font-size:13px; }
        h1 { font-size:17px; }
        /* 표가 기기 폭보다 넓으면 표만 가로로 민다 — 본문은 안 밀린다. */
        .tw { overflow-x:auto; -webkit-overflow-scrolling:touch; }
        .tw table { min-width:340px; }
        th,td { padding:6px 6px; white-space:nowrap; }
        td.desc, .tw td:not(.num) { white-space:normal; word-break:keep-all; }
        @media (prefers-color-scheme: dark) {
          body { background:#000; color:#e5e5e7; }
          th,td { border-color:#48484a; }
          thead th { background:#1c1c1e; color:#e5e5e7; }
          tr.total td { background:#1c1c1e; }
          .sub { color:#98989d; }
        }
        </style>
        """
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

    private static func buildMonthlyHTML(items: [ReportLineItem], opening: Int, startDate: Date, endDate: Date, forScreen: Bool) -> String {
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
        // 적요 칸의 이름과 묶는 규칙은 둘 다 `ReportLineItem` 이 정한다
        // (`reportLabel` · `mergesInReport`) — 분석 화면과 규칙이 갈리지 않게.
        //
        // 같은 날짜 + 같은 방향 + 같은 이름은 한 줄로 합산한다. 다만 **사람이 이름을
        // 준 줄만** 합친다. 분할 조각의 적요가 서로 다르면 안 합쳐지므로 예전보다
        // 줄이 늘 수 있는데, 그게 맞다 — 묶어 보낸 출금의 다섯 조각은 서로 다른
        // 사람에게 간 돈이라 한 줄로 뭉치면 누구에게 갔는지가 사라진다.
        var rows: [(label: String, isDeposit: Bool, amount: Int, day: Date)] = []
        var indexByKey: [String: Int] = [:]
        for it in sorted {
            let day = cal.startOfDay(for: it.datetime)
            let label = it.reportLabel
            guard it.mergesInReport else {
                rows.append((label, it.isDeposit, it.magnitude, day))
                continue
            }
            let key = "\(day.timeIntervalSince1970)|\(label)|\(it.isDeposit)"
            if let idx = indexByKey[key] {
                rows[idx].amount += it.magnitude
            } else {
                indexByKey[key] = rows.count
                rows.append((label, it.isDeposit, it.magnitude, day))
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
        </style>\(screenCSS(forScreen))</head><body>
        <h1>\(title)</h1>

        \(twOpen(forScreen))<table>
          <thead><tr><th>월</th><th>일</th><th>적요</th><th>수입</th><th>지출</th><th>잔액</th></tr></thead>
          <tbody>\(detail)</tbody>
        </table>\(twClose(forScreen))

        <div class='section-title'>수입 · 지출 요약</div>
        \(twOpen(forScreen))<table>
          <thead><tr><th colspan='2'>수입</th><th colspan='2'>지출</th></tr></thead>
          <tbody>\(summary)</tbody>
        </table>\(twClose(forScreen))
        </body></html>
        """
    }

    static func makeReceiptsPDF(items: [FinanceItem], startDate: Date, endDate: Date) async -> URL? {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        // (라벨, 이미지 URL) 목록 구성. **영수증은 항목이 갖는다.**
        struct Entry { let label: String; let url: String }
        var entries: [Entry] = []
        for item in items.sorted(by: { $0.datetime < $1.datetime }) {
            let receipts = item.receipts
            for (i, urlString) in receipts.enumerated() {
                var label = "\(dateFmt.string(from: item.datetime)) · \(item.description ?? "-") · \(won(abs(item.amount)))"
                if let cat = item.category, !cat.isEmpty { label += " · \(cat)" }
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
