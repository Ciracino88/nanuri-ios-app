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
    /// 장부 목록을 한 번이라도 받아 봤는지. **"아직 모른다" 와 "정말 없다" 를 가른다.**
    /// 이걸 안 두면 받아 오는 사이에 "장부가 없어요" 화면이 깜빡 스친다.
    @Published private(set) var ledgersLoaded = false
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

    // MARK: - 잔액은 저장하지 않고 유도한다

    /// 한 통장의 잔액. 개시잔액에서 시작해 그 통장을 지나간 돈을 전부 더한다.
    ///
    /// **내부 이체는 한 줄이 양쪽 통장에 걸친다.** `accountId` 쪽은 적힌 부호 그대로,
    /// `counterAccountId` 쪽은 **부호를 뒤집어** 더해야 두 통장 잔액이 모두 맞는다.
    /// (농협에서 −400만이면 모임에서는 +400만이다)
    func balance(of account: Account, asOf date: Date? = nil) -> Int {
        var sum = account.openingBalance
        for tx in transactions {
            if let date, tx.datetime > date { continue }
            if tx.accountId == account.id {
                sum += tx.amount
            } else if tx.counterAccountId == account.id {
                sum -= tx.amount
            }
        }
        return sum
    }

    /// 총 재정 = 모든 통장의 잔액 합.
    ///
    /// 내부 이체는 한쪽에서 빠지고 다른 쪽에 더해져 **저절로 상쇄된다.**
    /// 그래서 따로 걸러낼 필요가 없다.
    func totalBalance(asOf date: Date? = nil) -> Int {
        accounts.reduce(0) { $0 + balance(of: $1, asOf: date) }
    }

    /// 이 달에 **통장 사이를 오간 돈.** 보낸 통장 → 받은 통장 방향별로 합친다.
    ///
    /// `filtered` 에서 내부 이체만 골라 낸 것이라 합계·보고서가 쓰는
    /// `filteredExternal` 의 **여집합**이다. 통장 화면만 이걸 본다 — 통장별 잔액과
    /// 그 달 합계가 왜 다른지를 설명하는 게 이 수의 유일한 쓸모다.
    ///
    /// 부호가 방향을 정한다. `amount` 가 음수면 적힌 통장에서 나간 것이고,
    /// 양수면 상대 통장에서 들어온 것이다.
    var internalTransferFlows: [AccountFlow] {
        var sums: [AccountFlow.Direction: Int] = [:]
        for tx in filtered {
            guard let counter = tx.counterAccountId else { continue }
            let direction = tx.amount < 0
                ? AccountFlow.Direction(from: tx.accountId, to: counter)
                : AccountFlow.Direction(from: counter, to: tx.accountId)
            sums[direction, default: 0] += abs(tx.amount)
        }
        return sums
            .map { AccountFlow(direction: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

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
    /// **내부 이체는 여기 안 들어온다** (`filteredExternal`).
    var reportItems: [ReportLineItem] {
        filteredExternal.flatMap { tx -> [ReportLineItem] in
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

    /// 이 달이 시작될 때의 총 잔액 (= 월별 보고서의 전월이월).
    ///
    /// 예전에는 `첫거래.balance − 첫거래.amount` 로 구했다. 거래마다 은행이 계산한
    /// 잔액이 박혀 있던 시절의 방법인데, **두 통장을 한 장부에 적으면서 그 칸이
    /// 어느 통장의 잔액도 아니게 되어** 없앴다.
    ///
    /// 지금은 **통장 개시잔액 합 + 그 달 이전의 실제 수입·지출**로 유도한다.
    /// 내부 이체는 더하지 않는다 — 한 통장에서 나가 다른 통장으로 들어가므로
    /// 장부 전체로는 0이고, 더하면 한쪽만 세어 이월액이 틀어진다.
    var openingBalance: Int {
        let opening = accounts.reduce(0) { $0 + $1.openingBalance }
        let before = transactions
            .filter { $0.datetime < startDate && !$0.isInternalTransfer }
            .reduce(0) { $0 + $1.amount }
        return opening + before
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

    // MARK: - 요약이 쓰는 값들

    /// 지난달 총 출금. **비교할 지난달이 아예 없으면 `nil`** 이다.
    ///
    /// 0 을 돌려주면 "지난달보다 전부 더 썼다" 는 문장이 나오는데, 그건 지난달에
    /// 안 쓴 게 아니라 **장부가 그때부터 시작하지 않았다**는 뜻일 수 있다.
    /// 둘을 구분해야 해서 `Optional` 이다.
    var previousMonthWithdrawal: Int? {
        let cal = Calendar.current
        guard let previous = cal.date(byAdding: .month, value: -1, to: currentMonth) else { return nil }
        let start = cal.startOfMonth(previous)
        let end = cal.endOfMonth(previous)
        let items = transactions.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !items.isEmpty else { return nil }
        return items.reduce(0) { $0 + abs($1.amount) }
    }

    /// 지난달과 견준 한 문장·색. 요약 밴드와 분석 화면이 이걸 같이 쓴다.
    var comparison: SpendingComparison {
        SpendingComparison(previousWithdrawal: previousMonthWithdrawal,
                           totalWithdrawal: totalWithdrawal,
                           totalDeposit: totalDeposit)
    }

    /// 이 달 출금(또는 입금)을 카테고리로 묶어 **큰 것부터** 돌려준다.
    ///
    /// `reportItems` 로 센다 — 한 거래를 여러 항목으로 쪼갠 분할 거래는 조각마다
    /// 카테고리가 다르므로, **거래 단위로 세면 통째로 첫 조각의 카테고리에 들어간다.**
    /// 묶는 이름은 `ReportLineItem.categoryLabel` 이 정해서 보고서와 같은 규칙을 탄다.
    ///
    /// 금액이 같으면 이름순이다. 순서가 매번 흔들리면 같은 달을 다시 열었을 때
    /// 막대의 색이 자리를 바꾼다.
    func categoryTotals(deposit: Bool) -> [CategoryTotal] {
        var sums: [String: Int] = [:]
        for item in reportItems where item.isDeposit == deposit {
            sums[item.categoryLabel, default: 0] += item.magnitude
        }
        return sums
            .map { CategoryTotal(name: $0.key, amount: $0.value) }
            .sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    /// 이 달에 있는 날들 (1일 → 말일). 날짜 셀렉터가 훑는 축이다.
    ///
    /// 거래가 없는 날도 뺀 자리를 남긴다 — 건너뛰면 날짜 간격이 들쭉날쭉해져서
    /// 어느 날이 비었는지가 안 보인다.
    var daysInCurrentMonth: [Date] {
        let cal = Calendar.current
        var days: [Date] = []
        var cursor = cal.startOfDay(for: startDate)
        let last = cal.startOfDay(for: endDate)
        while cursor <= last {
            days.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// 이 달을 덮는 주들 (일요일 시작). 날짜 셀렉터가 한 주씩 넘긴다.
    ///
    /// 달 경계에 걸친 주는 **이전·다음 달 날짜까지 그대로 들고 온다** — 한 주는
    /// 일곱 칸이어야 요일 자리가 안 흔들린다. 그 칸들은 이 달 밖이라 눌리지 않는다.
    var weeksInCurrentMonth: [[Date]] {
        var cal = Calendar.current
        cal.firstWeekday = 1  // 일요일 시작
        let days = daysInCurrentMonth
        guard let first = days.first, let last = days.last else { return [] }
        guard let firstWeek = cal.dateInterval(of: .weekOfYear, for: first) else { return [] }

        var weeks: [[Date]] = []
        var cursor = cal.startOfDay(for: firstWeek.start)
        while cursor <= last {
            var week: [Date] = []
            for offset in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: cursor) else { break }
                week.append(cal.startOfDay(for: day))
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }

    /// 그 날이 지금 보고 있는 달에 속하는가. 주 단위로 끊다 보면 앞뒤 달이 섞인다.
    func isInCurrentMonth(_ day: Date) -> Bool {
        day >= Calendar.current.startOfDay(for: startDate) && day <= endDate
    }

    /// 달 시작부터 하루씩 쌓은 **누적 출금**. 그래프가 쓴다.
    ///
    /// `monthsAgo: 0` 이 이 달, `1` 이 지난달이다. 그 달에 거래가 없으면 빈 배열이라
    /// 그래프가 선을 안 그린다.
    func cumulativeWithdrawals(monthsAgo: Int) -> [Int] {
        let cal = Calendar.current
        guard let month = cal.date(byAdding: .month, value: -monthsAgo, to: currentMonth) else { return [] }
        let start = cal.startOfMonth(month)
        let end = cal.endOfMonth(month)
        let items = transactions.filter {
            $0.datetime >= start && $0.datetime <= end
                && !$0.isDeposit && !$0.isInternalTransfer
        }
        guard !items.isEmpty else { return [] }

        var perDay: [Int: Int] = [:]
        for tx in items {
            let day = cal.component(.day, from: tx.datetime)
            perDay[day, default: 0] += abs(tx.amount)
        }
        let dayCount = cal.component(.day, from: end)
        var running = 0
        return (1...dayCount).map { day in
            running += perDay[day] ?? 0
            return running
        }
    }

    /// 날짜별 순증감 (입금 − 출금). 거래가 없는 날은 키가 없다.
    var dailyNet: [Date: Int] {
        let cal = Calendar.current
        var result: [Date: Int] = [:]
        for tx in filteredExternal {
            let day = cal.startOfDay(for: tx.datetime)
            result[day, default: 0] += tx.isDeposit ? tx.amount : -abs(tx.amount)
        }
        return result
    }

    // MARK: - 장부

    /// 재정 탭이 열릴 때 부른다. 장부를 받아 **하나를 바로 연다.**
    ///
    /// 장부를 고르는 화면이 따로 없다. 통장이 하나라서 고를 것이 없고, 하나뿐인 걸
    /// 매번 손으로 고르게 하는 건 아무 뜻이 없다. 그래서 목록을 받는 즉시 연다.
    ///
    /// 장부가 여럿이면 **가장 최근 것**을 연다 (`fetchLedgers` 가 `created_at desc`).
    /// 지금은 그럴 일이 없지만, 그때 조용히 아무것도 안 여는 것보다는 낫다.
    ///
    /// 이미 열어 둔 장부가 있으면 아무 일도 안 한다 — 탭을 오갈 때마다 다시 받으면
    /// 보고 있던 달이 처음으로 되돌아간다 (`selectLedger` 가 달 위치를 다시 잡는다).
    func start() async {
        guard currentLedger == nil else { return }
        await fetchLedgers()
        ledgersLoaded = true
        guard let first = ledgers.first else { return }
        await selectLedger(first)
    }

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
    func createLedger(name: String) async -> Ledger? {
        do {
            let created: Ledger = try await supabase
                .from("finance_ledgers")
                .insert(LedgerInsert(name: name))
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

    /// 장부를 선택하고 그 장부의 통장과 거래를 불러온다.
    ///
    /// **통장을 거래보다 먼저 받는다.** 잔액이 저장값이 아니라 개시잔액에서 유도되는
    /// 값이라, 통장이 없으면 거래가 다 있어도 잔액이 전부 0에서 시작한 것처럼 보인다.
    func selectLedger(_ ledger: Ledger) async {
        currentLedger = ledger
        needsInitialMonth = true   // 장부가 바뀌면 그 장부의 마지막 달로 다시 맞춘다
        await fetchAccounts()
        await fetchTransactions()
    }

    func fetchAccounts() async {
        guard let ledgerId = currentLedger?.id else {
            accounts = []
            return
        }
        do {
            accounts = try await supabase
                .from("finance_accounts")
                .select()
                .eq("ledger_id", value: ledgerId)
                .order("sort_order", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("통장 조회 실패: \(error.localizedDescription)")
        }
    }

    /// 이름으로 통장 찾기. 통장이 둘뿐이라 이름이 곧 식별자 노릇을 한다.
    func account(named name: String) -> Account? {
        accounts.first { $0.name == name }
    }

    // MARK: - 내보내기

    /// 화면(웹뷰)에 띄울 보고서 HTML. PDF와 같은 표를 같은 코드로 만든다.
    func reportHTML() -> String? {
        guard currentLedger != nil else {
            error = "장부를 먼저 선택해주세요."
            return nil
        }
        return FinanceReportExporter.makeReportHTML(
            items: reportItems, opening: openingBalance,
            startDate: startDate, endDate: endDate, forScreen: true
        )
    }

    /// 현재 기간의 거래내역을 선택한 모드에 맞는 PDF 보고서로 만든다 (영수증 미포함).
    func exportReportPDF() -> URL? {
        guard let ledger = currentLedger else {
            error = "장부를 먼저 선택해주세요."
            return nil
        }
        guard let url = FinanceReportExporter.makeReportPDF(
            items: reportItems, opening: openingBalance,
            startDate: startDate, endDate: endDate, ledgerName: ledger.name
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

    /// 파싱한 거래내역서를 거래로 저장한다.
    ///
    /// **거래내역서는 모임통장 것이다** — 토스뱅크에서 뽑는 것이고, 농협은 종이
    /// 거래내역을 보고 손으로 적는다. 그래서 모임 통장에 붙인다.
    ///
    /// 이 경로는 앞으로 **대조**로 바뀔 자리다. 지금처럼 거래를 만들어 넣으면 앱이
    /// 통장을 그대로 베끼는 셈이라 통장과 대조해 봐야 늘 같다 — 검증이 아니라 복사다.
    /// 사람이 적은 장부와 통장이 따로 있어야 어긋난 곳이 드러난다.
    /// (`ParsedStatementLine` 이 은행 잔액을 들고 있는 게 그때 쓰인다)
    private func saveTransactions(_ items: [ParsedStatementLine]) async {
        guard let ledgerId = currentLedger?.id else {
            error = "장부를 먼저 선택해주세요."
            isLoading = false
            return
        }
        guard let account = account(named: "모임") else {
            error = "모임통장을 찾을 수 없어요."
            isLoading = false
            return
        }
        let rows = items.map {
            BankTransactionInsert(
                ledgerId: ledgerId,
                accountId: account.id,
                datetime: $0.datetime,
                type: $0.type,
                amount: $0.amount,
                description: $0.description
            )
        }
        do {
            // upsert 가 아니라 insert 다. 중복을 막던 `unique (ledger_id, datetime,
            // amount)` 제약을 뺐다 — 그건 PDF 재파싱용이었고, 수기 입력에서는 같은 날
            // 같은 금액 거래 둘(8월 모임통장의 볼링장 결제 같은)이 서로를 막았다.
            try await supabase
                .from("finance_transactions")
                .insert(rows)
                .execute()
            await fetchTransactions()
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래 저장 실패: \(error.localizedDescription)")
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
            Log.finance.error("원본 PDF 보관 실패: \(error.localizedDescription)")
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
