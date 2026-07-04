import SwiftUI

struct ContentView: View {
    @StateObject private var financeViewModel = FinanceViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            BillListView()
                .tabItem { Label("청구서", systemImage: "doc.text") }
                .tag(0)
            SurveyListView()
                .tabItem { Label("설문", systemImage: "chart.bar.doc.horizontal") }
                .tag(1)
            FinanceView(viewModel: financeViewModel)
                .tabItem { Label("재정", systemImage: "wonsign.circle") }
                .tag(2)
        }
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "pdf" else { return }
            selectedTab = 2
            financeViewModel.handleIncomingPDF(url: url)
        }
    }
}
