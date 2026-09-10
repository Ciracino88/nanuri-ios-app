import Foundation
import Supabase
import OSLog

extension FinanceViewModel {

    // MARK: - 불러오기

    /// 재정 탭이 처음 열릴 때 부른다. 통장을 먼저, 그다음 거래·항목을 받는다.
    ///
    /// **통장을 항목보다 먼저 받는다.** 잔액이 저장값이 아니라 개시잔액에서 유도되는
    /// 값이라, 통장이 없으면 항목이 다 있어도 잔액이 전부 0에서 시작한 것처럼 보인다.
    ///
    /// 이미 받아 둔 게 있으면 아무 일도 안 한다 — 탭을 오갈 때마다 다시 받으면 보고
    /// 있던 달이 처음으로 되돌아간다.
    func start() async {
        guard !loaded else { return }
        await fetchAccounts()
        await fetchTransactions()
        loaded = true
    }

    func fetchAccounts() async {
        do {
            accounts = try await supabase
                .from("finance_accounts")
                .select()
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

    /// 거래(은행 증명)와 항목(장부)을 함께 받는다. 편집·불러오기 뒤에도 이걸 다시 부른다.
    func fetchTransactions() async {
        isLoading = true
        error = nil
        do {
            transactions = try await supabase
                .from("finance_transactions")
                .select()
                .order("datetime", ascending: false)
                .execute()
                .value
            items = try await supabase
                .from("finance_items")
                .select()
                .order("datetime", ascending: false)
                .execute()
                .value
            positionAtLatestMonthIfNeeded()
        } catch {
            self.error = error.localizedDescription
            Log.finance.error("재정 조회 실패: \(error.localizedDescription)")
        }
        isLoading = false
    }
}
