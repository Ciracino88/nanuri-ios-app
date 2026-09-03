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
                // **손으로 넣은 거래의 적요는 사람이 쓴 값이다.** 그래서 분할 조각과
                // 같은 자리(`lineDescription`)에 놓아 이름으로도 쓰이고 같은 날 같은
                // 적요끼리 합쳐지기도 한다 — ATM 에서 세 번 나눠 뽑은 18만원이
                // 장부에서 한 줄이 되는 게 그것이다.
                //
                // 거래내역서에서 온 거래는 다르다. 그 적요는 은행이 준 값
                // (`이충성`·`우성볼링장`)이라 줄마다 달라서, 이름으로 쓰면 묶음이
                // 통째로 무너진다. `sourceDescription` 에만 둔다.
                let written = tx.source == .manual ? tx.description : nil
                return [ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                                       magnitude: abs(tx.amount), category: tx.category,
                                       lineDescription: written, sourceDescription: tx.description)]
            }
            return splits.map {
                ReportLineItem(datetime: tx.datetime, isDeposit: tx.isDeposit,
                               magnitude: $0.amount, category: $0.category,
                               lineDescription: $0.description, sourceDescription: tx.description)
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
    /// 거래는 **통장에 찍힌 그대로** 넣고(적요도 은행 값 그대로), 장부에 적힐 줄은
    /// **분할**로 만든다. 청구가 하나뿐일 때도 분할을 만든다 — 그래야 은행 적요를
    /// 덮어쓰지 않고 장부 줄에 제 이름을 줄 수 있다.
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

            // 장부에 적힐 줄은 **분할**로 만든다. 무엇이 조각이 되는지는
            // `StatementMatch.ledgerLines` 가 정한다 — 청구 묶음의 제목들이거나,
            // 사람이 적은 적요 한 줄이거나, 내부 이체면 없다. 화면이 미리 보여준
            // 것과 저장되는 것이 같아야 해서 그 계산을 한 곳에 뒀다.
            //
            // **청구가 하나뿐일 때도 조각을 만든다.** 그래야 은행 적요를 덮어쓰지
            // 않고 장부 줄에 제 이름을 줄 수 있다.
            var splitInserts: [TransactionSplitInsert] = []
            for match in todo {
                let lines = match.ledgerLines
                guard !lines.isEmpty else { continue }
                guard let tx = created.first(where: {
                    $0.amount == match.line.amount
                        && abs($0.datetime.timeIntervalSince(match.line.datetime)) < 1
                }) else { continue }
                // 분류는 이 줄에서 나온 **모든 조각에 같이** 붙는다. 청구엔 없는
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

    // MARK: - 거래 쓰기

    /// 거래를 손으로 넣는다.
    ///
    /// **농협은 이 길뿐이다.** 인터넷뱅킹이 없어 거래내역 파일이 안 나오므로 사람이
    /// 앱 화면을 보고 옮겨 적는 수밖에 없다. 2026-08 기준 농협 25건 / 모임 22건이라
    /// **절반은 영영 수기다** — 한 건 넣는 데 손이 많이 가면 안 쓰게 된다.
    ///
    /// 넣은 뒤 목록을 다시 받지 않고 **돌려받은 행을 그 자리에 꽂는다.** 연달아
    /// 넣는 화면이라 한 건마다 273건을 다시 받으면 입력이 끊긴다.
    @discardableResult
    func addTransaction(
        accountId: UUID,
        counterAccountId: UUID? = nil,
        datetime: Date,
        amount: Int,
        description: String?,
        category: String?
    ) async -> Bool {
        guard let ledgerId = currentLedger?.id else {
            error = "장부를 먼저 선택해주세요."
            return false
        }
        let row = BankTransactionInsert(
            ledgerId: ledgerId,
            accountId: accountId,
            counterAccountId: counterAccountId,
            datetime: datetime,
            // 토스가 주는 값(이자입금·체크카드결제·ATM출금…)과 달리 손으로 넣는 건
            // 부호만으로 충분하다. 통장에 찍힌 유형이 아니라 사람이 적는 줄이다.
            type: amount >= 0 ? "입금" : "출금",
            amount: amount,
            description: description,
            category: category,
            source: .manual
        )
        do {
            let created: BankTransaction = try await supabase
                .from("finance_transactions")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            transactions.append(created)
            // `fetchTransactions` 가 datetime 내림차순으로 받으므로 같은 순서를 지킨다.
            transactions.sort { $0.datetime > $1.datetime }
            return true
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래 추가 실패: \(error.localizedDescription)")
            return false
        }
    }

    /// 거래를 지운다. 분할은 `on delete cascade` 로 같이 사라진다.
    ///
    /// **영수증을 먼저 지운다.** 청구서 삭제와 같은 순서이고 이유도 같다 — 행이
    /// 먼저 사라지면 이미지 삭제가 실패했을 때 R2 에 주인 없는 파일이 남고 그 URL 을
    /// 아는 사람이 없어진다. 반대 순서면 최악이 "이미지는 지워졌는데 행이 남는"
    /// 것이고, 그건 눈에 보여서 다시 지울 수 있다.
    func deleteTransaction(_ transaction: BankTransaction) async {
        for url in transaction.receipts {
            await ReceiptStorage.delete(receiptUrl: url)
        }
        do {
            try await supabase
                .from("finance_transactions")
                .delete()
                .eq("id", value: transaction.id)
                .execute()
            transactions.removeAll { $0.id == transaction.id }
            splitsByTransaction[transaction.id] = nil
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("거래 삭제 실패: \(error.localizedDescription)")
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
        datetime: Date,
        amount: Int,
        description: String?,
        accountId: UUID,
        counterAccountId: UUID?,
        category: String?,
        keptUrls: [String],
        newImages: [UIImage],
        originalUrls: [String],
        splits: [(category: String?, amount: Int, description: String?)] = []
    ) async {
        // 거래내역서에서 온 거래는 **금액·일시·통장이 통장의 기록**이다. 화면이
        // 그 칸을 잠그지만, 잠그는 판단은 여기서도 한 번 더 한다 — 규칙이 화면에만
        // 있으면 화면이 하나 더 생길 때 조용히 새어 나간다.
        let existing = transactions.first { $0.id == id }
        let locked = existing?.isFromStatement ?? false
        let finalDatetime = locked ? (existing?.datetime ?? datetime) : datetime
        let finalAmount   = locked ? (existing?.amount ?? amount) : amount
        let finalAccount  = locked ? (existing?.accountId ?? accountId) : accountId
        let finalCounter  = locked ? existing?.counterAccountId : counterAccountId
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

        // 2. DB 반영 (한 번에)
        do {
            try await supabase
                .from("finance_transactions")
                .update(TransactionEditUpdate(
                    datetime: finalDatetime, amount: finalAmount, description: description,
                    category: category, receiptUrls: finalUrls,
                    accountId: finalAccount, counterAccountId: finalCounter
                ))
                .eq("id", value: id)
                .execute()
            if let idx = transactions.firstIndex(where: { $0.id == id }) {
                transactions[idx].datetime = finalDatetime
                transactions[idx].amount = finalAmount
                transactions[idx].description = description
                transactions[idx].accountId = finalAccount
                transactions[idx].counterAccountId = finalCounter
                transactions[idx].category = category
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
                                           category: s.category, description: s.description,
                                           sortOrder: index)
                }
                try await supabase.from("finance_splits").insert(inserts).execute()
                splitsByTransaction[id] = splits.enumerated().map { index, s in
                    TransactionSplit(id: UUID(), transactionId: id, amount: s.amount,
                                     category: s.category, description: s.description,
                                     sortOrder: index)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }


}
