import SwiftUI

struct ContentView: View {
    @StateObject private var financeViewModel = FinanceViewModel()
    /// 청구서 탭과 계좌부 탭이 같은 목록을 봐야 한다. 각자 만들면 한쪽에서 등록한
    /// 계좌가 다른 쪽에 안 보인다.
    @StateObject private var payeeViewModel = PayeeViewModel()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var incomingFile = IncomingFile.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            BillListView(payeeViewModel: payeeViewModel)
                .tabItem { Label("청구서", systemImage: "doc.text") }
                .tag(0)
            FinanceView(viewModel: financeViewModel)
                .tabItem { Label("재정", systemImage: "wonsign.circle") }
                .tag(1)
            PayeeListView(viewModel: payeeViewModel)
                .tabItem { Label("계좌부", systemImage: "person.text.rectangle") }
                .tag(2)
            ProfileView()
                .tabItem { Label("프로필", systemImage: "person.crop.circle") }
                .tag(3)
        }
        // 루트가 받아 둔 파일을 꺼내 간다. 두 자리에서 부르는 이유는 도착 시점이
        // 둘이라서다 — 앱이 켜지면서 들어오면 이 화면이 뜰 때(`onAppear`) 이미
        // 담겨 있고, 앱이 떠 있는 채로 들어오면 그때 바뀐다(`onChange`).
        .onAppear { consumeIncomingPDF() }
        .onChange(of: incomingFile.pendingPDF) { _, _ in consumeIncomingPDF() }
        // 로그인한 뒤에 부른다. 토큰을 저장하려면 auth.uid() 가 필요하다.
        .task {
            await PushManager.shared.requestAuthorizationAndRegister()
            await NotificationStore.shared.syncFromNotificationCenter()
        }
        // 앱이 꺼져 있는 동안 온 알림은 다시 켤 때만 주울 수 있다.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await NotificationStore.shared.syncFromNotificationCenter() }
        }
    }

    /// 들어온 거래내역서를 재정 탭으로 데려간다. 담긴 게 없으면 아무 일도 안 한다.
    private func consumeIncomingPDF() {
        guard let url = incomingFile.consume() else { return }
        selectedTab = 1
        financeViewModel.handleIncomingPDF(url: url)
    }
}
