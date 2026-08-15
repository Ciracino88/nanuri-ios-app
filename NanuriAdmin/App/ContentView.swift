import SwiftUI

struct ContentView: View {
    @StateObject private var financeViewModel = FinanceViewModel()
    /// 청구서 탭과 계좌부 탭이 같은 목록을 봐야 한다. 각자 만들면 한쪽에서 등록한
    /// 계좌가 다른 쪽에 안 보인다.
    @StateObject private var payeeViewModel = PayeeViewModel()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

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
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "pdf" else { return }
            selectedTab = 1
            financeViewModel.handleIncomingPDF(url: url)
        }
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
}
