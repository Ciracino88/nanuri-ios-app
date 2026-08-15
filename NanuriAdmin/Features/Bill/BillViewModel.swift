import SwiftUI
import Combine
import Supabase

@MainActor
class BillViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    @Published var isLoading = false
    @Published var error: String?

    func subscribeToRealtime() async {
        let channel = supabase.channel("bills-realtime")

        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "bills")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "bills")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "bills")

        await channel.subscribe()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in inserts { await self.fetchBills(showLoading: false) }
            }
            group.addTask {
                for await _ in updates { await self.fetchBills(showLoading: false) }
            }
            group.addTask {
                for await _ in deletes { await self.fetchBills(showLoading: false) }
            }
        }
    }

    func fetchBills(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        do {
            bills = try await supabase
                .from("bills")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
            print("청구서 조회 실패: \(error)")
        }
        isLoading = false
    }

    func updateStatus(billId: UUID, status: String) async {
        do {
            try await supabase
                .from("bills")
                .update(["status": status])
                .eq("id", value: billId.uuidString)
                .execute()
            await fetchBills(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            print("상태 변경 실패: \(error)")
        }
    }

    func deleteBill(billId: UUID, receiptUrl: String?) async {
        do {
            // 1. Cloudflare R2 이미지 삭제 (공용 서비스 재사용)
            if let receiptUrl, !receiptUrl.isEmpty {
                await ReceiptStorage.delete(receiptUrl: receiptUrl)
            }

            // 2. Supabase DB 삭제
            try await supabase
                .from("bills")
                .delete()
                .eq("id", value: billId.uuidString)
                .execute()

            await fetchBills(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            print("청구서 삭제 실패: \(error)")
        }
    }

    /// 계좌부에서 찾은 수취인으로 토스 송금 화면을 연다.
    /// 이름이 계좌부에 없으면 호출되지 않는다 (UI에서 먼저 막는다).
    func openToss(bill: Bill, payee: Payee) {
        let accountNumber = payee.accountNumber.replacingOccurrences(of: "-", with: "")
        let bankName = payee.bankName

        guard !accountNumber.isEmpty, !bankName.isEmpty else {
            print("계좌 정보 없음")
            return
        }

        let urlString = "supertoss://send?bank=\(bankName)&accountNo=\(accountNumber)&amount=\(bill.amount)"
        print("토스 URL: \(urlString)")
        guard let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encoded) else {
            print("URL 생성 실패")
            return
        }
        UIApplication.shared.open(url) { success in
            print("토스 앱 열기 결과: \(success)")
        }
    }
}
