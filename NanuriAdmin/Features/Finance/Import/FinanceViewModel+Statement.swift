import Foundation
import PDFKit
import Supabase
import OSLog

extension FinanceViewModel {

    /// 공유로 들어온 토스뱅크 PDF를 **곧바로 확인 화면으로 보낸다.**
    ///
    /// 보관하지 않는다. 원본은 파일 앱에 있으므로 다시 필요하면 다시 공유하면 된다
    /// (`incomingStatement` 주석 참고).
    func handleIncomingPDF(url: URL) {
        error = nil
        incomingStatement = IncomingStatement(url: url)
    }

    // MARK: - 거래내역서 불러오기 (청구 매칭)

    /// 승인된 청구를 전부 받아 묶음으로 만든다.
    ///
    /// 기간을 안 자른다 — 청구는 한 달에 스무 건 남짓이라 다 받아도 가볍고,
    /// 자르면 **승인이 다음 달로 넘어간 건**(체크카드는 26시간까지 벌어진다)을
    /// 놓친다.
    func fetchBillGroups() async -> [BillGroup] {
        do {
            let bills: [Bill] = try await supabase
                .from("bills")
                .select()
                .eq("status", value: "approved")
                .execute()
                .value
            return StatementMatcher.groups(from: bills)
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("청구 조회 실패: \(error.localizedDescription)")
            return []
        }
    }

    /// 거래내역서를 파싱하고 청구와 맞춰 본다. **아직 아무것도 저장하지 않는다** —
    /// 사람이 확인하고 고칠 자리를 준 뒤에 넣는다.
    func prepareStatementImport(from url: URL) async -> [StatementMatch] {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let pdf = PDFDocument(url: url) else {
            error = "PDF 파일을 열 수 없습니다."
            return []
        }
        var fullText = ""
        for i in 0..<pdf.pageCount {
            fullText += (pdf.page(at: i)?.string ?? "") + "\n"
        }
        let lines = TossPdfParser.parse(fullText)
        guard !lines.isEmpty else {
            error = "거래내역을 파싱할 수 없습니다."
            return []
        }
        let groups = await fetchBillGroups()
        return StatementMatcher.matches(lines: lines, groups: groups,
                                        existing: transactions, accounts: accounts)
    }

    /// 확인이 끝난 것을 장부에 넣는다.
    ///
    /// 거래(은행 증명)는 **통장에 찍힌 그대로** 넣고, 장부에 적힐 것은 **항목**으로
    /// 만든다. 무엇이 항목이 되는지는 `StatementMatch.itemSpecs` 가 정한다 — 청구
    /// 묶음의 제목들이거나, 사람이 적은 적요 한 줄이거나, 내부 이체 한 줄이거나,
    /// 아무것도 없으면 통짜 한 줄이다. **모든 거래는 최소 한 항목으로 완전히 풀려야**
    /// 은행 증명(거래)과 장부(항목)가 대조된다.
    ///
    /// 거래를 한 번에 넣고 돌려받은 행을 **금액·시각으로 되찾아** 항목을 붙인다.
    /// 돌아오는 순서를 믿지 않는다.
    func importStatement(_ matches: [StatementMatch], into account: Account) async {
        let todo = matches.filter { !$0.alreadyImported }
        guard !todo.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let rows = todo.map { match in
            BankTransactionInsert(
                accountId: account.id,
                datetime: match.line.datetime,
                type: match.line.type,
                amount: match.line.amount,
                description: match.line.description
            )
        }
        do {
            let created: [BankTransaction] = try await supabase
                .from("finance_transactions")
                .insert(rows)
                .select()
                .execute()
                .value

            // 거래마다 항목을 만든다. `itemSpecs` 가 청구 묶음의 영수증까지 항목별로
            // 실어 준다 — 청구가 이미 갖고 있는 것을 항목이 복사해 받는 것이라
            // 사람이 다시 찍어 올릴 일이 없다.
            var itemInserts: [FinanceItemInsert] = []
            for match in todo {
                guard let tx = created.first(where: {
                    $0.amount == match.line.amount
                        && abs($0.datetime.timeIntervalSince(match.line.datetime)) < 1
                }) else { continue }
                for (index, spec) in match.itemSpecs(txAmount: tx.amount).enumerated() {
                    itemInserts.append(FinanceItemInsert(
                        accountId: account.id,
                        datetime: tx.datetime,
                        amount: spec.amount,
                        isInternalTransfer: spec.isInternalTransfer,
                        category: spec.category,
                        description: spec.description,
                        receiptUrls: spec.receiptUrls,
                        sourceTransactionId: tx.id,
                        sortOrder: index
                    ))
                }
            }
            if !itemInserts.isEmpty {
                try await supabase.from("finance_items").insert(itemInserts).execute()
            }
            await fetchTransactions()
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래내역서 반영 실패: \(error.localizedDescription)")
        }
    }
}
