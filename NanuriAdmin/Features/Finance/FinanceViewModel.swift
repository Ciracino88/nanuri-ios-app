import SwiftUI
import Combine
import PDFKit
import UIKit
import Supabase
import OSLog

@MainActor
class FinanceViewModel: ObservableObject {
    /// **은행 증명 — 거래내역서 줄들.** 편집 안 하는 불변 기록이다. 목록은 이걸 직접
    /// 그리지 않는다(항목이 그린다). 불러오기 중복 판정과, 항목의 부모 맥락에 쓴다.
    @Published var transactions: [BankTransaction] = []
    /// **장부 정본 — 항목들.** 잔액·보고서·목록이 전부 여기서 나온다.
    @Published var items: [FinanceItem] = []
    /// 통장들 (농협·모임). 잔액을 유도하는 출발점이라 항목보다 먼저 있어야 한다.
    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var error: String?
    /// 한 번이라도 받아 봤는지. **"아직 모른다" 와 "정말 없다" 를 가른다.**
    @Published var loaded = false

    /// 목록 정렬. 켜면 오래된 순, 끄면(기본) 최신순이다.
    @Published var oldestFirst = false
    /// 지금 보고 있는 달 (그 달 1일 0시).
    @Published var currentMonth = Calendar.current.startOfMonth(Date())
    /// 아직 한 번도 달을 맞춰 주지 않았는가. (자료가 있는 마지막 달로 한 번만 데려간다)
    var needsInitialMonth = true

    /// 보고 있는 달의 시작·끝. 보고서와 영수증 부록도 이걸 그대로 쓴다.
    var startDate: Date { currentMonth }
    var endDate: Date { Calendar.current.endOfMonth(currentMonth) }

    /// 공유로 막 들어온 거래내역서. **비어 있지 않으면 확인 화면이 떠 있다는 뜻이다.**
    @Published var incomingStatement: IncomingStatement?

    /// 거래를 id 로 찾는다. 항목이 자기 부모 거래(은행 증명)를 되짚을 때 쓴다.
    private var transactionsById: [UUID: BankTransaction] {
        Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
    }

    /// 이 항목의 은행 증명(부모 거래). 농협 수기 항목은 `nil`.
    func transaction(for item: FinanceItem) -> BankTransaction? {
        guard let sid = item.sourceTransactionId else { return nil }
        return transactionsById[sid]
    }

    /// 지금 보고 있는 달의 항목 **전부**. 목록이 쓴다 — 내부 이체도 보여야 한다.
    var filtered: [FinanceItem] {
        items.filter { $0.datetime >= startDate && $0.datetime <= endDate }
    }

    /// 그중 **실제 수입·지출만.** 합계·보고서·그래프는 전부 이걸 쓴다.
    /// 통장 사이를 옮긴 돈은 장부 전체로 보면 나간 것도 들어온 것도 아니다.
    var filteredExternal: [FinanceItem] { filtered.filter { !$0.isInternalTransfer } }

    var deposits: [FinanceItem] { filteredExternal.filter { $0.isDeposit } }
    var withdrawals: [FinanceItem] { filteredExternal.filter { !$0.isDeposit } }

    /// 목록이 그리는 **항목들.** 정렬은 여기서 한 번 건다.
    var ledgerRows: [LedgerRow] { rows(of: filtered) }
    var depositRows: [LedgerRow] { rows(of: deposits) }
    var withdrawalRows: [LedgerRow] { rows(of: withdrawals) }

    /// **카테고리가 비어 있는 항목.** 목록에서 골라 한 번에 붙이라고 모아 준다.
    /// 내부 이체는 뺀다 — 카테고리를 붙일 항목이 아니고, 앞으로도 안 붙는다.
    var uncategorizedRows: [LedgerRow] {
        ledgerRows.filter {
            !$0.isInternalTransfer
                && ($0.category?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }

    /// 항목을 정렬해 목록 줄로 싼다. 한 거래에서 나온 조각들은 `sort_order` 를
    /// 지키고(같은 시각이므로), 그 위에 시각 순서를 얹는다.
    private func rows(of source: [FinanceItem]) -> [LedgerRow] {
        let ordered = source.sorted { a, b in
            if a.datetime != b.datetime {
                return oldestFirst ? a.datetime < b.datetime : a.datetime > b.datetime
            }
            return a.sortOrder < b.sortOrder
        }
        return ordered.map { LedgerRow(item: $0, transaction: transaction(for: $0)) }
    }
}
