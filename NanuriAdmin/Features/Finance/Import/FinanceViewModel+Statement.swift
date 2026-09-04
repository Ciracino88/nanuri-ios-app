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
    /// 거래는 **통장에 찍힌 그대로** 넣고(적요도 은행 값 그대로), 장부에 적힐 항목은
    /// **분할**로 만든다. 청구가 하나뿐일 때도 분할을 만든다 — 그래야 은행 적요를
    /// 덮어쓰지 않고 항목에 제 이름을 줄 수 있다.
    ///
    /// 거래를 한 번에 넣고 돌려받은 행을 **금액·시각으로 되찾아** 분할을 붙인다.
    /// 돌아오는 순서를 믿지 않는다.
    func importStatement(_ matches: [StatementMatch], into account: Account) async {
        guard let ledgerId = currentLedger?.id else {
            error = "장부를 먼저 선택해주세요."
            return
        }
        let todo = matches.filter { !$0.alreadyImported }
        guard !todo.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        let rows = todo.map { match in
            BankTransactionInsert(
                ledgerId: ledgerId,
                accountId: account.id,
                // 통장 사이 이체면 상대 통장을 적는다. **한 줄이 양쪽을 안다** —
                // 이 칸이 차 있으면 합계·보고서에서 저절로 빠지고, 상대 통장 잔액도
                // 부호를 뒤집어 여기서 유도된다.
                counterAccountId: match.isInternalTransfer ? match.counterAccountId : nil,
                datetime: match.line.datetime,
                type: match.line.type,
                amount: match.line.amount,
                description: match.line.description,
                // 고른 청구 묶음의 영수증을 그대로 물려준다. 청구가 이미 갖고 있는
                // 것을 거래가 다시 받는 것이라 사람이 다시 찍어 올릴 일이 없다.
                receiptUrls: match.chosen?.receiptUrls ?? [],
                source: .statement
            )
        }
        do {
            let created: [BankTransaction] = try await supabase
                .from("finance_transactions")
                .insert(rows)
                .select()
                .execute()
                .value

            // 장부에 적힐 항목은 **분할**로 만든다. 무엇이 조각이 되는지는
            // `StatementMatch.ledgerLines` 가 정한다 — 청구 묶음의 제목들이거나,
            // 사람이 적은 적요 한 줄이거나, 내부 이체면 없다. 화면이 미리 보여준
            // 것과 저장되는 것이 같아야 해서 그 계산을 한 곳에 뒀다.
            //
            // **청구가 하나뿐일 때도 조각을 만든다.** 그래야 은행 적요를 덮어쓰지
            // 않고 항목에 제 이름을 줄 수 있다.
            var splitInserts: [TransactionSplitInsert] = []
            for match in todo {
                let lines = match.ledgerLines
                guard !lines.isEmpty else { continue }
                guard let tx = created.first(where: {
                    $0.amount == match.line.amount
                        && abs($0.datetime.timeIntervalSince(match.line.datetime)) < 1
                }) else { continue }
                // 카테고리는 이 줄에서 나온 **모든 조각에 같이** 붙는다. 청구엔 없는
                // 값이라 사람이 확인 화면에서 준 것뿐이다.
                let category = match.manualCategory.trimmingCharacters(in: .whitespaces)
                for (index, line) in lines.enumerated() {
                    splitInserts.append(TransactionSplitInsert(
                        transactionId: tx.id,
                        amount: line.amount,
                        category: category.isEmpty ? nil : category,
                        description: line.title,
                        sortOrder: index
                    ))
                }
            }
            if !splitInserts.isEmpty {
                try await supabase.from("finance_splits").insert(splitInserts).execute()
            }
            await fetchTransactions()
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래내역서 반영 실패: \(error.localizedDescription)")
        }
    }
}
