import SwiftUI
import Combine
import Supabase

/// 계좌부. 인원이 많아야 수십 명이라 전부 메모리에 올려두고 이름으로 찾는다.
@MainActor
class PayeeViewModel: ObservableObject {
    @Published var payees: [Payee] = []
    @Published var isLoading = false
    @Published var error: String?

    /// 정규화한 이름 → 계좌. fetch 할 때마다 다시 만든다.
    private var index: [String: Payee] = [:]

    /// 청구서의 이름으로 계좌를 찾는다. 공백·대소문자는 무시한다.
    func payee(for name: String) -> Payee? {
        index[name.normalizedName]
    }

    func fetchPayees(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        do {
            let rows: [Payee] = try await supabase
                .from("payees")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
            payees = rows
            index = Dictionary(
                rows.map { ($0.name.normalizedName, $0) },
                // 정규화 후 충돌하는 이름은 DB 유니크 인덱스가 막아주지만,
                // 혹시 남아 있다면 먼저 온 쪽을 쓴다.
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            self.error = error.localizedDescription
            print("계좌부 조회 실패: \(error)")
        }
        isLoading = false
    }

    func save(_ payee: PayeeUpsert, id: UUID?) async -> Bool {
        do {
            if let id {
                try await supabase
                    .from("payees")
                    .update(payee)
                    .eq("id", value: id.uuidString)
                    .execute()
            } else {
                try await supabase
                    .from("payees")
                    .insert(payee)
                    .execute()
            }
            await fetchPayees(showLoading: false)
            return true
        } catch {
            // 유니크 인덱스 위반이면 이미 같은 이름이 있다는 뜻이다.
            self.error = "\(payee.name) 은(는) 이미 등록된 이름이거나, 저장에 실패했어요."
            print("계좌부 저장 실패: \(error)")
            return false
        }
    }

    func delete(id: UUID) async {
        do {
            try await supabase
                .from("payees")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            await fetchPayees(showLoading: false)
        } catch {
            self.error = error.localizedDescription
            print("계좌부 삭제 실패: \(error)")
        }
    }
}
