import SwiftUI

struct ContentView: View {
    @StateObject private var financeViewModel = FinanceViewModel()
    /// 청구서 탭과 계좌부 탭이 같은 목록을 봐야 한다. 각자 만들면 한쪽에서 등록한
    /// 계좌가 다른 쪽에 안 보인다.
    @StateObject private var payeeViewModel = PayeeViewModel()
    @State private var selectedTab = 0

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
