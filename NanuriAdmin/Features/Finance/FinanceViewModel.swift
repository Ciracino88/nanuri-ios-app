import SwiftUI
import Combine
import PDFKit
import Supabase

@MainActor
class FinanceViewModel: ObservableObject {
    @Published var transactions: [BankTransaction] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var savedStatements: [StatementFile] = []

    var filtered: [BankTransaction] {
        transactions.filter {
            $0.datetime >= startDate && $0.datetime <= endDate
        }
    }

    var deposits: [BankTransaction] { filtered.filter { $0.isDeposit } }
    var withdrawals: [BankTransaction] { filtered.filter { !$0.isDeposit } }

    /// 지금까지 입력된 카테고리를 사용 빈도순으로 반환 (편집 시 추천용).
    var usedCategories: [String] {
        let all = transactions
            .compactMap { $0.category?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let counts = Dictionary(grouping: all, by: { $0 }).mapValues { $0.count }
        return counts.keys.sorted { counts[$0]! > counts[$1]! }
    }
    var totalDeposit: Int { deposits.reduce(0) { $0 + $1.amount } }
    var totalWithdrawal: Int { withdrawals.reduce(0) { $0 + abs($1.amount) } }

    func fetchTransactions() async {
        isLoading = true
        error = nil
        do {
            let result: [BankTransaction] = try await supabase
                .from("finance_transactions")
                .select()
                .order("datetime", ascending: false)
                .execute()
                .value
            transactions = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func handleIncomingPDF(url: URL) {
        isLoading = true
        error = nil

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        // 파싱과 별개로 원본 PDF를 앱에 먼저 보관한다 (파싱 누락 대비 안전장치).
        let savedURL = persistOriginalPDF(from: url)
        loadSavedStatements()

        processPDF(at: savedURL ?? url)
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

        let parsed = parsePdfText(fullText)
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
        do {
            try await supabase
                .from("finance_transactions")
                .upsert(items, onConflict: "datetime,amount")
                .execute()
            await fetchTransactions()
        } catch {
            self.error = error.localizedDescription
            print("저장 실패: \(error)")
            isLoading = false
        }
    }

    func updateTransaction(id: UUID, category: String?, memo: String?) async {
        do {
            try await supabase
                .from("finance_transactions")
                .update(BankTransactionUpdate(category: category, memo: memo))
                .eq("id", value: id)
                .execute()
            if let idx = transactions.firstIndex(where: { $0.id == id }) {
                transactions[idx].category = category
                transactions[idx].memo = memo
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

    private func parsePdfText(_ text: String) -> [BankTransactionInsert] {
        // 물리적 줄 단위로 처리한다.
        // - 날짜로 시작하는 줄 = 새 거래 (줄 안의 공백은 정당한 공백이므로 보존)
        // - 날짜로 시작하지 않는 줄 = 앞 거래 description의 줄바꿈 연속 → 공백 없이 이어붙임
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 한 줄 = [날짜][구분][금액][잔액] (그 뒤 description은 줄 끝까지 또는 다음 줄로 이어짐)
        // 구분값은 특정 단어로 열거하지 않고 "한글/영문 글자 토큰"이면 무엇이든 받는다.
        // (입금/출금/이자입금 외에 처음 보는 유형도 누락 없이 잡기 위함)
        let headerPattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+([가-힣A-Za-z]+)\s+(-?[\d,]+)\s+([\d,]+)\s*(.*)$"#
        guard let headerRegex = try? NSRegularExpression(pattern: headerPattern) else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ko_KR")

        // 거래 사이에 끼는 표 머리글/발급 정보 등은 description으로 붙이지 않는다.
        let footerPrefixes = ["거래일자", "발급일자", "페이지", "토스뱅크", "계좌번호"]

        var result: [BankTransactionInsert] = []
        var pending: (datetime: Date, type: String, amount: Int, balance: Int, desc: String)?

        func flush() {
            guard let p = pending else { return }
            let cleaned = p.desc.trimmingCharacters(in: .whitespaces)
            result.append(BankTransactionInsert(
                datetime: p.datetime,
                type: p.type,
                amount: p.amount,
                balance: p.balance,
                description: cleaned.isEmpty ? nil : cleaned
            ))
            pending = nil
        }

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)

            if let m = headerRegex.firstMatch(in: line, range: range),
               let dtR = Range(m.range(at: 1), in: line),
               let tyR = Range(m.range(at: 2), in: line),
               let amR = Range(m.range(at: 3), in: line),
               let baR = Range(m.range(at: 4), in: line),
               let datetime = formatter.date(from: String(line[dtR])) {
                // 새 거래 시작 → 이전 거래 확정
                flush()

                let amount = Int(String(line[amR]).replacingOccurrences(of: ",", with: "")) ?? 0
                let balance = Int(String(line[baR]).replacingOccurrences(of: ",", with: "")) ?? 0
                var inlineDesc = ""
                if let dR = Range(m.range(at: 5), in: line) {
                    inlineDesc = String(line[dR])
                }
                pending = (datetime, String(line[tyR]), amount, balance, inlineDesc)
            } else if footerPrefixes.contains(where: { line.hasPrefix($0) }) {
                // 표 머리글·발급 정보 등 → 현재 거래를 확정하고 무시
                flush()
            } else if pending != nil {
                // description 줄바꿈 연속 → 공백 없이 이어붙임 (예: "후원" + "금" = "후원금")
                pending!.desc += line
            }
        }
        flush()
        return result
    }
}
