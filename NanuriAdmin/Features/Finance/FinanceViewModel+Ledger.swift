import Foundation
import Supabase
import OSLog

extension FinanceViewModel {

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
}
