import SwiftUI

/// 편집 중인 분할 항목 (저장 시 finance_splits로 반영).
///
/// `description` 이 **이 조각의 적요**다 — 보고서 상세 명세의 적요 칸에 그대로 찍힌다.
/// 거래에는 이런 자유 입력 칸이 없다 — 있었지만 어디에도 안 보여서 걷어냈다.
struct SplitDraft: Identifiable {
    var id = UUID()
    var category: String
    var amount: Int
    var description: String
}

/// 분할 항목 하나를 입력·편집하는 바텀 시트.
struct SplitEditSheet: View {
    let initial: SplitDraft
    let isNew: Bool
    let suggestions: [String]
    let txMagnitude: Int
    let otherSum: Int
    let onSave: (SplitDraft) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var category: String
    @State private var amount: Int
    @State private var itemDescription: String

    init(initial: SplitDraft, isNew: Bool, suggestions: [String], txMagnitude: Int, otherSum: Int,
         onSave: @escaping (SplitDraft) -> Void, onDelete: @escaping () -> Void) {
        self.initial = initial
        self.isNew = isNew
        self.suggestions = suggestions
        self.txMagnitude = txMagnitude
        self.otherSum = otherSum
        self.onSave = onSave
        self.onDelete = onDelete
        _category = State(initialValue: initial.category)
        _amount = State(initialValue: initial.amount)
        _itemDescription = State(initialValue: initial.description)
    }

    private var remainingForFull: Int { max(txMagnitude - otherSum, 0) }

    var body: some View {
        NavigationView {
            Form {
                Section("카테고리") {
                    TextField("예: 회비, 식대, 시상품", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                }
                Section("금액") {
                    TextField("금액", value: $amount, format: .number)
                        .keyboardType(.numberPad)
                    HStack {
                        Text("거래액 \(txMagnitude.formatted())원 · 다른 항목 \(otherSum.formatted())원")
                            .typeStyle(DS.Typo.body3)
                            .tabularAmount()
                            .foregroundColor(DS.Ink.secondary)
                        Spacer()
                        Button("남은 전액") { amount = remainingForFull }
                            .typeStyle(DS.Typo.labelS)
                            .foregroundColor(DS.Ink.brand)
                    }
                }
                // 이 칸이 보고서의 적요다 — 묶어 보낸 출금을 쪼갤 때 조각마다
                // 받는 사람이 다르므로, 여기가 비면 그 줄은 카테고리로만 불린다.
                Section("적요") {
                    TextField("예: 8월 수련회 식대 (홍길동)", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("이 항목 삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "항목 추가" : "항목 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isNew ? "추가" : "완료") {
                        onSave(SplitDraft(id: initial.id, category: category,
                                          amount: amount, description: itemDescription))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
