import SwiftUI
import Combine
import Supabase

@MainActor
class BillViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    @Published var isLoading = false
    @Published var error: String?
    
    let cfWorkerUrl = "https://nanuri-bill.church-worker.workers.dev"

    func fetchBills() async {
        isLoading = true
        do {
            let user = try await supabase.auth.user()
            print("현재 유저 ID: \(user.id)")
            print("현재 유저 이메일: \(user.email ?? "없음")")
            
            var bills: [Bill] = try await supabase
                .from("bills")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            // user_profiles 따로 조회
            let userIds = bills.map { $0.userId.uuidString }
            let profiles: [ProfileRow] = try await supabase
                .from("user_profiles")
                .select("id, name, account_number, bank_name")
                .in("id", values: userIds)
                .execute()
                .value

            // bills에 profile 매핑
            let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            self.bills = bills.map { bill in
                var b = bill
                if let p = profileMap[bill.userId] {
                    b.userProfile = UserProfile(name: p.name, accountNumber: p.accountNumber ?? "", bankName: p.bankName ?? "")
                }
                return b
            }

            print("청구서 조회 성공: \(self.bills.count)개")
        } catch {
            self.error = error.localizedDescription
            print("청구서 조회 실패: \(error)")
        }
        isLoading = false
    }

    func updateStatus(billId: UUID, status: String) async {
        do {
            print("상태 변경 시도: \(billId) → \(status)")
            try await supabase
                .from("bills")
                .update(["status": status])
                .eq("id", value: billId.uuidString)
                .execute()
            print("상태 변경 성공")
            await fetchBills()
        } catch {
            self.error = error.localizedDescription
            print("상태 변경 실패: \(error)")
        }
    }
    
    func deleteBill(billId: UUID, receiptUrl: String) async {
        do {
            // 1. Cloudflare R2 이미지 삭제
            if let workerUrl = URL(string: "\(cfWorkerUrl)/delete") {
                var request = URLRequest(url: workerUrl)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONEncoder().encode(["receiptUrl": receiptUrl])
                _ = try? await URLSession.shared.data(for: request)
            }

            // 2. Supabase DB 삭제
            try await supabase
                .from("bills")
                .delete()
                .eq("id", value: billId.uuidString)
                .execute()

            await fetchBills()
            print("청구서 삭제 성공")
        } catch {
            self.error = error.localizedDescription
            print("청구서 삭제 실패: \(error)")
        }
    }

    func openToss(bill: Bill) {
        let accountNumber = (bill.accountNumber ?? bill.userProfile?.accountNumber ?? "").replacingOccurrences(of: "-", with: "")
        let bankName = bill.bankName ?? bill.userProfile?.bankName ?? ""
        
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
