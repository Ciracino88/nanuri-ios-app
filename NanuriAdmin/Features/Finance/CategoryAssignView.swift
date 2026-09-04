import SwiftUI

/// 고른 줄들에 붙일 분류를 정하는 시트.
///
/// **이미 쓴 이름을 먼저 보여준다.** 새로 치는 것보다 고르는 게 빠르고, 같은 뜻에
/// 이름이 둘 생기는 것(`행사비`·`행사 비용`)을 막는다 — 그러면 보고서 요약이
/// 두 줄로 갈린다.
struct CategoryAssignView: View {
    let suggestions: [String]
    let count: Int
    let onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("카테고리 (예: 회비, 행사비, 심방비)", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                } footer: {
                    Text("\(count)줄에 같이 붙어요. 비워 두고 누르면 분류가 지워져요.")
                }
            }
            .navigationTitle("분류 붙이기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("붙이기") {
                        onApply(category)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
