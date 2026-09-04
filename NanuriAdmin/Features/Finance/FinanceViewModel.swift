import SwiftUI
import Combine
import PDFKit
import UIKit
import Supabase
import OSLog

@MainActor
class FinanceViewModel: ObservableObject {
    @Published var transactions: [BankTransaction] = []
    @Published var isLoading = false
    @Published var error: String?
    /// 목록 정렬. 켜면 오래된 순, 끄면(기본) 최신순이다.
    ///
    /// **여기 하나만 바꾸면 네 칩(전체·입금·출금·미지정)이 모두 따라간다** —
    /// 네 목록이 전부 `ledgerRows(of:)` 를 지나가기 때문이다. 합계·보고서·그래프는
    /// 순서와 무관한 집계라 건드리지 않는다.
    @Published var oldestFirst = false
    /// 지금 보고 있는 달 (그 달 1일 0시).
    ///
    /// 수기 장부가 **시트 하나 = 한 달**이었고 보고서도 월 단위라, 화면도 달을 하나씩
    /// 넘겨 본다. 임의 기간을 고르는 자리는 두지 않는다 — 월별 회계 보고서에서
    /// "3월 12일 ~ 5월 2일" 같은 구간은 전월이월이 뜻을 잃어 읽을 수 없는 표가 된다.
    @Published var currentMonth = Calendar.current.startOfMonth(Date())
    /// 장부를 고른 뒤 아직 한 번도 달을 맞춰 주지 않았는가.
    /// (거래를 받아오면 자료가 있는 마지막 달로 한 번만 데려간다)
    var needsInitialMonth = true

    /// 보고 있는 달의 시작·끝. 보고서와 영수증 부록도 이걸 그대로 쓴다.
    var startDate: Date { currentMonth }

    var endDate: Date { Calendar.current.endOfMonth(currentMonth) }

    /// 공유로 막 들어온 거래내역서. **비어 있지 않으면 확인 화면이 떠 있다는 뜻이다.**
    ///
    /// 예전에는 파일을 `Documents/Statements` 에 보관하고 목록에서 골라 불러왔다.
    /// 그 목록은 "보고서 모드를 고른 뒤에 불러온다" 는 게이트 때문에 있던 대기실인데,
    /// **행사 모드(`abb7989`)와 장부 고르는 화면(`a0ebef7`)이 없어지면서 고를 게
    /// 사라졌다.** 재파싱도 `f503bd0` 에서 지웠고, 원본은 파일 앱에 그대로 있다.
    /// 그래서 사본을 쌓지 않고 **들어오는 즉시 확인 화면으로 보낸다.**
    @Published var incomingStatement: IncomingStatement?
    @Published var splitsByTransaction: [UUID: [TransactionSplit]] = [:]
    @Published var ledgers: [Ledger] = []
    /// 장부 목록을 한 번이라도 받아 봤는지. **"아직 모른다" 와 "정말 없다" 를 가른다.**
    /// 이걸 안 두면 받아 오는 사이에 "장부가 없어요" 화면이 깜빡 스친다.
    @Published var ledgersLoaded = false
    @Published var currentLedger: Ledger?
    /// 이 장부의 통장들 (농협·모임). 잔액을 유도하는 출발점이라 거래보다 먼저 있어야 한다.
    @Published var accounts: [Account] = []

    /// 지금 보고 있는 달의 거래 **전부**. 목록이 쓴다 — 내부 이체도 보여야 한다.
    /// 400만원을 옮긴 사실이 화면에서 사라지면 그게 더 이상하다.
    var filtered: [BankTransaction] {
        transactions.filter {
            $0.datetime >= startDate && $0.datetime <= endDate
        }
    }

    /// 그중 **실제 수입·지출만.** 합계·보고서·그래프는 전부 이걸 쓴다.
    ///
    /// 통장 사이를 옮긴 돈은 장부 전체로 보면 나간 것도 들어온 것도 아니다.
    /// 안 빼면 그 달이 부풀어 보인다 (`BankTransaction.isInternalTransfer` 참고).
    var filteredExternal: [BankTransaction] { filtered.filter { !$0.isInternalTransfer } }

    var deposits: [BankTransaction] { filteredExternal.filter { $0.isDeposit } }

    var withdrawals: [BankTransaction] { filteredExternal.filter { !$0.isDeposit } }

    /// 목록이 그리는 **항목들.** 분할이 있으면 조각마다 한 항목이다.
    ///
    /// 칩의 개수도 이걸 센다 — 엑셀 장부의 줄 수와 같은 수가 나와야 한다.
    var ledgerRows: [LedgerRow] { ledgerRows(of: filtered) }

    var depositRows: [LedgerRow] { ledgerRows(of: deposits) }

    var withdrawalRows: [LedgerRow] { ledgerRows(of: withdrawals) }

    /// **카테고리가 비어 있는 항목.** 목록에서 골라 한 번에 붙이라고 모아 준다.
    ///
    /// 내부 이체는 뺀다 — 카테고리를 붙일 항목이 아니고, 앞으로도 안 붙는다.
    /// 그걸 세면 "아직 12항목 남았다" 가 영영 0이 안 된다.
    var uncategorizedRows: [LedgerRow] {
        ledgerRows.filter {
            !$0.isInternalTransfer
                && ($0.category?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }

    /// 거래를 항목으로 편다. **내부 이체는 안 쪼갠다** — 사람 장부에 없는 줄이라
    /// 조각이 애초에 없고, 그 사실이 화면에서도 한 항목으로 남아야 한다.
    private func ledgerRows(of items: [BankTransaction]) -> [LedgerRow] {
        // 정렬은 여기서 한 번만 건다. 분할 조각은 `splits(for:)` 가 매기는
        // `sort_order` 를 그대로 지킨다 — 한 거래 안에서의 순서는 뒤집지 않는다.
        let ordered = oldestFirst
            ? items.sorted { $0.datetime < $1.datetime }
            : items.sorted { $0.datetime > $1.datetime }
        return ordered.flatMap { tx -> [LedgerRow] in
            let pieces = splits(for: tx.id)
            guard !pieces.isEmpty, !tx.isInternalTransfer else {
                return [LedgerRow(transaction: tx, split: nil)]
            }
            return pieces.map { LedgerRow(transaction: tx, split: $0) }
        }
    }

    /// 특정 거래의 분할 항목 (없으면 빈 배열).
    func splits(for transactionId: UUID) -> [TransactionSplit] {
        (splitsByTransaction[transactionId] ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}
