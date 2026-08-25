import Foundation
import Combine
import Supabase
import OSLog

/// 청구서 목록의 상태를 갖는다. 조회 · 상태 변경 · 삭제 · 실시간 구독까지가 이 객체의 일이다.
///
/// 토스 송금은 여기 없다. URL 을 만드는 건 상태가 필요 없는 순수 로직이라
/// `TossDeepLink` 로 나가 있다.
@MainActor
class BillViewModel: ObservableObject {
    @Published var bills: [Bill] = []
    @Published var isLoading = false
    @Published var error: String?

    /// 실시간 구독을 돌리는 태스크. **화면이 아니라 이 객체가 들고 있는다.**
    private var realtimeTask: Task<Void, Never>?

    deinit {
        realtimeTask?.cancel()
    }

    // MARK: - 실시간 구독

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
    ///
    /// ## 끊는 함수는 일부러 없다
    ///
    /// 이 뷰모델은 청구서 탭이 사는 동안 = 앱이 켜져 있는 동안 산다. 끊을 시점이
    /// 없는데 `stop()` 을 열어 두면 **"언제 부르지?"** 가 생기고, 잘못된 시점에
    /// 불리면 위의 버그로 그대로 돌아간다.
    ///
    /// 정말 끊어야 할 날이 오면 태스크만 취소해서는 안 된다. `supabase.removeChannel`
    /// 로 **채널까지 지워야** 한다 — 안 그러면 SDK 캐시에 구독된 채널이 남아서
    /// 다음 구독이 또 조용히 죽는다.
    func subscribeToRealtime() {
        guard realtimeTask == nil else { return }

        let channel = supabase.channel("bills-realtime")

        // 콜백은 subscribe() 보다 **먼저** 붙어야 한다. 순서가 바뀌면 조인 payload 에
        // postgres_changes 가 비어서 아무 이벤트도 안 온다.
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "bills")
        let updates = channel.postgresChange(UpdateAction.self, schema: "public", table: "bills")
        let deletes = channel.postgresChange(DeleteAction.self, schema: "public", table: "bills")

        realtimeTask = Task { [weak self] in
            await channel.subscribe()

            // 세 스트림 중 무엇이 오든 하는 일은 같다 — 목록을 다시 받는다.
            // 이벤트의 payload 를 직접 반영하지 않는 이유는, 그러면 정렬·필터·
            // RLS 결과를 클라이언트가 다시 계산해야 하고 그게 서버와 어긋날 수 있어서다.
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

    // MARK: - 조회 / 변경

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
            report(error, "청구서 조회")
        }
        isLoading = false
    }

    func updateStatus(billId: UUID, status: String) async {
        await updateStatus(billIds: [billId], status: status)
    }

    /// 묶어서 송금한 여러 건을 한 번에 처리한다.
    ///
    /// **한 요청으로 보내야 한다.** 건별로 나눠 보내면 중간에 끊길 때 일부만 완료로
    /// 남고, 나머지가 다시 청구된 것처럼 보인다.
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
            report(error, "상태 변경")
        }
    }

    /// 청구서와 영수증 이미지를 같이 지운다.
    ///
    /// 이미지를 **먼저** 지운다. 순서를 바꾸면 DB 행이 사라진 뒤 이미지 삭제가
    /// 실패했을 때 R2 에 주인 없는 파일이 남고, 그 URL 을 아는 사람이 없어서
    /// 다시 지울 방법이 없다. 반대 순서면 최악이 "이미지는 지워졌는데 행이 남는"
    /// 것이고, 그건 눈에 보여서 다시 지울 수 있다.
    func deleteBill(billId: UUID, receiptUrl: String?) async {
        do {
            if let receiptUrl, !receiptUrl.isEmpty {
                await ReceiptStorage.delete(receiptUrl: receiptUrl)
            }

            try await supabase
                .from("bills")
                .delete()
                .eq("id", value: billId.uuidString)
                .execute()

            await fetchBills(showLoading: false)
        } catch {
            report(error, "청구서 삭제")
        }
    }

    // MARK: -

    /// 화면에 띄울 문구와 로그를 한자리에서 처리한다.
    ///
    /// 무엇을 하다 실패했는지(`what`)는 `.public` 으로 남기고, 서버가 준 메시지는
    /// 청구자 이름 같은 게 섞일 수 있어 기본값(가려짐) 그대로 둔다.
    /// Xcode 로 붙어 있을 때는 가려진 값도 그대로 보인다.
    private func report(_ error: Error, _ what: String) {
        self.error = error.localizedDescription
        Log.bill.error("\(what, privacy: .public) 실패: \(error.localizedDescription)")
    }
}
