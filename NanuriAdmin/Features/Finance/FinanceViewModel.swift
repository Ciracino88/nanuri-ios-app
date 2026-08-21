import SwiftUI
import Combine
import PDFKit
import UIKit
import Supabase

@MainActor
class FinanceViewModel: ObservableObject {
    @Published var transactions: [BankTransaction] = []
    @Published var isLoading = false
    @Published var error: String?
    /// 지금 보고 있는 달 (그 달 1일 0시).
    ///
    /// 수기 장부가 **시트 하나 = 한 달**이었고 보고서도 월 단위라, 화면도 달을 하나씩
    /// 넘겨 본다. 임의 기간을 고르는 자리는 두지 않는다 — 월별 회계 보고서에서
    /// "3월 12일 ~ 5월 2일" 같은 구간은 전월이월이 뜻을 잃어 읽을 수 없는 표가 된다.
    @Published var currentMonth = Calendar.current.startOfMonth(Date())
    /// 장부를 고른 뒤 아직 한 번도 달을 맞춰 주지 않았는가.
    /// (거래를 받아오면 자료가 있는 마지막 달로 한 번만 데려간다)
    private var needsInitialMonth = true

    /// 보고 있는 달의 시작·끝. 보고서와 영수증 부록도 이걸 그대로 쓴다.
    var startDate: Date { currentMonth }
    var endDate: Date { Calendar.current.endOfMonth(currentMonth) }
    @Published var savedStatements: [StatementFile] = []
    @Published var splitsByTransaction: [UUID: [TransactionSplit]] = [:]
    @Published var ledgers: [Ledger] = []
    @Published var currentLedger: Ledger?

    /// 행사 장부는 통장 전체가 한 행사이므로 날짜 필터를 적용하지 않는다.
    var filtered: [BankTransaction] {
        guard currentLedger?.mode != .event else { return transactions }
        return transactions.filter {
            $0.datetime >= startDate && $0.datetime <= endDate
        }
    }

    var deposits: [BankTransaction] { filtered.filter { $0.isDeposit } }
    var withdrawals: [BankTransaction] { filtered.filter { !$0.isDeposit } }

    // MARK: - 달 넘기기

    /// 넘겨 볼 수 있는 달들 (과거 → 현재). 거래가 한 건도 없는 중간 달도 포함한다 —
    /// 장부는 비어 있어도 그 달이 존재하고, 건너뛰면 이어지는 느낌이 끊긴다.
    ///
    /// 뒤쪽 끝은 **마지막 거래가 있는 달과 이번 달 중 나중**이다. 이번 달에 아직
    /// 거래가 없어도 열 수 있어야 하기 때문이다 (오늘 넣은 게 여기 뜬다).
    var selectableMonths: [Date] {
        let cal = Calendar.current
        let months = transactions.map { cal.startOfMonth($0.datetime) }
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
        return transactions.contains { cal.isDate($0.datetime, equalTo: month, toGranularity: .month) }
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
    private func positionAtLatestMonthIfNeeded() {
        guard needsInitialMonth else { return }
        needsInitialMonth = false
        let cal = Calendar.current
        if let latest = transactions.map({ cal.startOfMonth($0.datetime) }).max() {
            currentMonth = latest
        }
    }

    /// 특정 거래의 분할 항목 (없으면 빈 배열).
    func splits(for transactionId: UUID) -> [TransactionSplit] {
        (splitsByTransaction[transactionId] ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// 보고서용 항목: 분할이 있으면 분할들, 없으면 거래 자체.
    var reportItems: [ReportLineItem] {
        filtered.flatMap { tx -> [ReportLineItem] in
            let splits = splits(for: tx.id)
            guard !splits.isEmpty else {
                return [ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                                       magnitude: abs(tx.amount), category: tx.category,
                                       memo: tx.memo, sourceDescription: tx.description)]
            }
            return splits.map {
                ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                               magnitude: $0.amount, category: $0.category,
                               memo: $0.memo, sourceDescription: tx.description)
            }
        }
    }

    /// 기간 첫 거래 직전 잔액 (월별 보고서 전월이월).
    var openingBalance: Int {
        let sorted = filtered.sorted { $0.datetime < $1.datetime }
        return sorted.first.map { $0.balance - $0.amount } ?? 0
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

    // MARK: - 장부

    func fetchLedgers() async {
        do {
            ledgers = try await supabase
                .from("finance_ledgers")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func createLedger(name: String, mode: FinanceReportMode) async -> Ledger? {
        do {
            let created: Ledger = try await supabase
                .from("finance_ledgers")
                .insert(LedgerInsert(name: name, type: mode.rawValue))
                .select()
                .single()
                .execute()
                .value
            ledgers.insert(created, at: 0)
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func deleteLedger(_ ledger: Ledger) async {
        do {
            try await supabase.from("finance_ledgers").delete().eq("id", value: ledger.id).execute()
            ledgers.removeAll { $0.id == ledger.id }
            if currentLedger?.id == ledger.id { currentLedger = nil }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 장부를 선택하고 그 장부의 거래를 불러온다.
    func selectLedger(_ ledger: Ledger) async {
        currentLedger = ledger
        needsInitialMonth = true   // 장부가 바뀌면 그 장부의 마지막 달로 다시 맞춘다
        await fetchTransactions()
    }

    // MARK: - 내보내기

    /// 보고서가 덮는 기간. 화면 미리보기와 PDF가 **같은 기간**을 쓰도록 한 곳에 둔다.
    /// 행사 장부는 날짜 필터가 없으므로 실제 거래 기간을 보고서 기간으로 쓴다.
    private func reportRange(mode: FinanceReportMode) -> (start: Date, end: Date) {
        guard mode == .event else { return (startDate, endDate) }
        let dates = filtered.map { $0.datetime }
        return (dates.min() ?? startDate, dates.max() ?? endDate)
    }

    /// 화면(웹뷰)에 띄울 보고서 HTML. PDF와 같은 표를 같은 코드로 만든다.
    func reportHTML() -> String? {
        guard let ledger = currentLedger else {
            error = "장부를 먼저 선택해주세요."
            return nil
        }
        let range = reportRange(mode: ledger.mode)
        return FinanceReportExporter.makeReportHTML(
            mode: ledger.mode, items: reportItems, opening: openingBalance,
            startDate: range.start, endDate: range.end, ledgerName: ledger.name,
            forScreen: true
        )
    }

    /// 현재 기간의 거래내역을 선택한 모드에 맞는 PDF 보고서로 만든다 (영수증 미포함).
    func exportReportPDF() -> URL? {
        guard let ledger = currentLedger else {
            error = "장부를 먼저 선택해주세요."
            return nil
        }
        let range = reportRange(mode: ledger.mode)
        guard let url = FinanceReportExporter.makeReportPDF(
            mode: ledger.mode, items: reportItems, opening: openingBalance,
            startDate: range.start, endDate: range.end, ledgerName: ledger.name
        ) else {
            error = "보고서 생성에 실패했어요."
            return nil
        }
        return url
    }

    /// 현재 기간의 영수증 이미지를 모은 부록 PDF를 만든다.
    func exportReceiptsPDF() async -> URL? {
        guard let url = await FinanceReportExporter.makeReceiptsPDF(
            transactions: filtered, startDate: startDate, endDate: endDate
        ) else {
            error = "이 기간에 첨부된 영수증이 없거나 내보내기에 실패했어요."
            return nil
        }
        return url
    }

    func fetchTransactions() async {
        guard let ledgerId = currentLedger?.id else {
            transactions = []
            splitsByTransaction = [:]
            return
        }
        isLoading = true
        error = nil
        do {
            let result: [BankTransaction] = try await supabase
                .from("finance_transactions")
                .select()
                .eq("ledger_id", value: ledgerId)
                .order("datetime", ascending: false)
                .execute()
                .value
            transactions = result

            let ids = result.map { $0.id.uuidString }
            if ids.isEmpty {
                splitsByTransaction = [:]
            } else {
                let splitRows: [TransactionSplit] = try await supabase
                    .from("finance_splits")
                    .select()
                    .in("transaction_id", values: ids)
                    .execute()
                    .value
                splitsByTransaction = Dictionary(grouping: splitRows, by: { $0.transactionId })
            }
            positionAtLatestMonthIfNeeded()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 공유로 들어온 토스뱅크 PDF는 로컬(저장된 거래내역서)에 보관만 한다.
    /// 파싱·거래 반영은 사용자가 보고서 모드를 고른 뒤 '저장된 거래내역서'에서 직접 불러온다.
    /// (가져오기는 월별/행사 모드와 무관하므로 게이트와 분리)
    func handleIncomingPDF(url: URL) {
        error = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        _ = persistOriginalPDF(from: url)
        loadSavedStatements()
    }

    /// 보관된 거래내역서를 다시 파싱해 거래내역을 갱신한다 (원본은 이미 로컬에 있으므로 재보관하지 않음).
    func reparseStatement(_ statement: StatementFile) {
        isLoading = true
        error = nil
        processPDF(at: statement.url)
    }

    /// PDF에서 텍스트를 추출·파싱해 Supabase에 저장한다.
    private func processPDF(at url: URL) {
        guard let pdf = PDFDocument(url: url) else {
            error = "PDF 파일을 열 수 없습니다."
            isLoading = false
            return
        }

        var fullText = ""
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            fullText += (page.string ?? "") + "\n"
        }

        let parsed = TossPdfParser.parse(fullText)
        if parsed.isEmpty {
            error = "거래내역을 파싱할 수 없습니다."
            isLoading = false
            return
        }

        Task {
            await saveTransactions(parsed)
        }
    }

    private func saveTransactions(_ items: [BankTransactionInsert]) async {
        guard let ledgerId = currentLedger?.id else {
            error = "장부를 먼저 선택해주세요."
            isLoading = false
            return
        }
        let scoped = items.map { item -> BankTransactionInsert in
            var copy = item
            copy.ledgerId = ledgerId
            return copy
        }
        do {
            try await supabase
                .from("finance_transactions")
                .upsert(scoped, onConflict: "ledger_id,datetime,amount")
                .execute()
            await fetchTransactions()
        } catch {
            self.error = error.localizedDescription
            print("저장 실패: \(error)")
            isLoading = false
        }
    }

    // MARK: - 거래 편집 저장 (영수증 R2는 청구서와 동일한 저장소 재사용)

    /// 거래 편집을 한 번에 커밋한다.
    /// 저장 시점에만 R2 업로드/삭제와 DB 반영이 일어난다 (취소하면 아무 일도 없음).
    /// - Parameters:
    ///   - keptUrls: 유지할 기존 영수증 URL 목록
    ///   - newImages: 새로 추가한 이미지 (여기서 업로드)
    ///   - originalUrls: 편집 시작 시점의 영수증 목록 (제거분 계산용)
    func saveTransactionEdits(
        id: UUID,
        category: String?,
        memo: String?,
        keptUrls: [String],
        newImages: [UIImage],
        originalUrls: [String],
        splits: [(category: String?, amount: Int, memo: String?)] = []
    ) async {
        // 1. 새 이미지 업로드 (해상도 축소 후)
        var newlyUploaded: [String] = []
        for image in newImages {
            guard let jpeg = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.7) else { continue }
            if let uploaded = try? await ReceiptStorage.upload(
                imageData: jpeg,
                filename: "receipt.jpg",
                folder: "finance"
            ) {
                newlyUploaded.append(uploaded)
            }
        }

        let finalUrls = keptUrls + newlyUploaded

        // 2. DB 반영 (카테고리·메모·영수증 한 번에)
        do {
            try await supabase
                .from("finance_transactions")
                .update(TransactionEditUpdate(category: category, memo: memo, receiptUrls: finalUrls))
                .eq("id", value: id)
                .execute()
            if let idx = transactions.firstIndex(where: { $0.id == id }) {
                transactions[idx].category = category
                transactions[idx].memo = memo
                transactions[idx].receiptUrls = finalUrls
            }
        } catch {
            self.error = error.localizedDescription
            // DB 반영 실패 시 방금 올린 이미지는 롤백(R2에서 삭제)
            for url in newlyUploaded { await ReceiptStorage.delete(receiptUrl: url) }
            return
        }

        // 3. DB 반영 성공 후, 제거된 기존 영수증을 R2에서 삭제
        let removed = originalUrls.filter { !keptUrls.contains($0) }
        for url in removed { await ReceiptStorage.delete(receiptUrl: url) }

        // 4. 분할 항목 교체 (기존 삭제 후 새로 삽입)
        do {
            try await supabase.from("finance_splits").delete().eq("transaction_id", value: id).execute()
            if splits.isEmpty {
                splitsByTransaction[id] = nil
            } else {
                let inserts = splits.enumerated().map { index, s in
                    TransactionSplitInsert(transactionId: id, amount: s.amount,
                                           category: s.category, memo: s.memo, sortOrder: index)
                }
                try await supabase.from("finance_splits").insert(inserts).execute()
                splitsByTransaction[id] = splits.enumerated().map { index, s in
                    TransactionSplit(id: UUID(), transactionId: id, amount: s.amount,
                                     category: s.category, memo: s.memo, sortOrder: index)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - 원본 PDF 보관

    /// 보관 폴더 (Documents/Statements)
    private var statementsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Statements", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 들어온 PDF 원본을 보관 폴더에 복사하고 저장된 URL을 반환한다.
    private func persistOriginalPDF(from url: URL) -> URL? {
        let fm = FileManager.default
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        let originalName = url.deletingPathExtension().lastPathComponent
        let filename = "\(stamp.string(from: Date()))_\(originalName).pdf"
        let dest = statementsDirectory.appendingPathComponent(filename)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: url, to: dest)
            return dest
        } catch {
            print("원본 PDF 보관 실패: \(error)")
            return nil
        }
    }

    /// 보관된 거래내역서 목록을 최신순으로 불러온다.
    func loadSavedStatements() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: statementsDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            savedStatements = []
            return
        }
        savedStatements = files
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .map { fileURL in
                let created = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return StatementFile(url: fileURL, importedAt: created)
            }
            .sorted { $0.importedAt > $1.importedAt }
    }

    /// 보관된 거래내역서 삭제.
    func deleteStatement(_ statement: StatementFile) {
        try? FileManager.default.removeItem(at: statement.url)
        loadSavedStatements()
    }

}
