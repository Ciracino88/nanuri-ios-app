import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            BillListView()
                .tabItem {
                    Label("청구서", systemImage: "doc.text")
                }
            SurveyListView()
                .tabItem {
                    Label("설문", systemImage: "chart.bar.doc.horizontal")
                }
        }
    }
}
