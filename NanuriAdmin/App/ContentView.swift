import SwiftUI

struct ContentView: View {
    @StateObject private var financeViewModel = FinanceViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BillListView()
                .tabItem { Label("청구서", systemImage: "doc.text") }
                .tag(0)
            FinanceView(viewModel: financeViewModel)
                .tabItem { Label("재정", systemImage: "wonsign.circle") }
                .tag(1)
            GuideView()
                .tabItem { Label("안내", systemImage: "info.circle") }
                .tag(2)
        }
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "pdf" else { return }
            selectedTab = 1
            financeViewModel.handleIncomingPDF(url: url)
        }
        // 로그인한 뒤에 부른다. 토큰을 저장하려면 auth.uid() 가 필요하다.
        .task {
            await PushManager.shared.requestAuthorizationAndRegister()
        }
    }
}
