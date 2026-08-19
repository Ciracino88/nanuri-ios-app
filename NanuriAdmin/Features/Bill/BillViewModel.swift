import SwiftUI
import Combine
import Supabase

@MainActor
class BillViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    @Published var isLoading = false
    @Published var error: String?

    /// 실시간 구독을 돌리는 태스크와 그 채널. 화면이 아니라 이 객체가 들고 있는다.
    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?

    deinit {
        realtimeTask?.cancel()
    }

    /// 실시간 구독. **뷰가 아니라 뷰모델이 갖는다.**
    ///
    /// 예전에는 화면의 `.task` 안에서 이걸 통째로 돌렸는데, 탭을 옮기면 화면이
    /// 사라지면서 `.task` 가 취소되고 콜백이 떨어져 나갔다. 돌아와서 다시 부르면
    /// SDK 가 **토픽이 같은 채널을 캐시에서 그대로 돌려주는데**, 이미 구독된
    /// 채널에는 `postgresChange` 콜백을 못 붙인다 (SDK 가 경고만 찍고 빈 구독을
    /// 준다). 그래서 탭을 한 번 옮기면 그 뒤로 실시간이 조용히 죽어 있었다.
    /// 목록이 그럭저럭 맞아 보였던 건 탭에 돌아올 때 `fetchBills()` 를 같이
    /// 불렀기 때문이다.
    ///
    /// 그래서 구독은 뷰 생명주기와 떼어 놓고 **앱을 켠 뒤 한 번만** 만든다.
    /// 두 번째부터는 아무 일도 안 한다.
    func subscribeToRealtime() {
        guard realtimeTask == nil else { return }

        let channel = supabase.channel("bills-realtime")
        realtimeChannel = channel

        // 콜백은 subscribe() 보다 **먼저** 붙어야 한다. 순서가 바뀌면 조인 payload 에
        // postgres_changes 가 비어서 아무 이벤트도 안 온다.
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "bills")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "bills")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "bills")

        realtimeTask = Task { [weak self] in
            await channel.subscribe()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await _ in inserts { await self?.fetchBills(showLoading: false) }
                }
                group.addTask {
                    for await _ in updates { await self?.fetchBills(showLoading: false) }
                }
                group.addTask {
                    for await _ in deletes { await self?.fetchBills(showLoading: false) }
                }
            }
        }
    }

    /// 구독을 끊는다. 화면이 사라질 때가 아니라 **뷰모델이 없어질 때** 부른다.
    func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil

        guard let channel = realtimeChannel else { return }
        realtimeChannel = nil
        // 채널은 SDK 가 토픽으로 캐시해 둔다. 지우지 않으면 다음에 같은 토픽으로
        // 새 구독을 만들 때 죽은 채널이 그대로 나온다.
        Task { await supabase.removeChannel(channel) }
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
        await updateStatus(billIds: [billId], status: status)
    }

    /// 묶어서 송금한 여러 건을 한 번에 처리한다.
    /// 한 요청으로 보내야 중간에 끊겨도 일부만 완료로 남는 일이 없다.
    func updateStatus(billIds: [UUID], status: String) async {
        guard !billIds.isEmpty else { return }
        do {
            try await supabase
                .from("bills")
                .update(["status": status])
                .in("id", values: billIds.map(\.uuidString))
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

    /// 같은 사람이 낸 다른 **대기중** 청구서. 묶어서 한 번에 보낼 후보다.
    ///
    /// 이름 대조는 계좌부와 같은 규칙(`normalizedName`)을 쓴다. 여기만 다르게
    /// 맞추면 계좌는 찾았는데 묶음에서는 빠지는 일이 생긴다.
    func pendingSiblings(of bill: Bill) -> [Bill] {
        guard bill.isPending else { return [] }
        let key = bill.submitterName.normalizedName
        return bills
            .filter { $0.id != bill.id && $0.isPending && $0.submitterName.normalizedName == key }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 계좌부에서 찾은 수취인으로 토스 송금 화면을 연다.
    /// 이름이 계좌부에 없으면 호출되지 않는다 (UI에서 먼저 막는다).
    ///
    /// 여러 건을 넘기면 **금액을 합쳐 한 번만** 연다. 토스 딥링크는 수취인 한 명에
    /// 금액 하나라서, 사람이 여럿이면 묶을 수 없다 (같은 사람만 묶는 이유다).
    func openToss(bills: [Bill], payee: Payee) {
        let amount = bills.reduce(0) { $0 + $1.amount }
        let accountNumber = payee.accountNumber.replacingOccurrences(of: "-", with: "")
        let bankName = payee.bankName

        guard amount > 0, !accountNumber.isEmpty, !bankName.isEmpty else {
            print("계좌 정보 없음")
            return
        }

        let urlString = "supertoss://send?bank=\(bankName)&accountNo=\(accountNumber)&amount=\(amount)"
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
