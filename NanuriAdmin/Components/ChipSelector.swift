import SwiftUI

/// 가로로 늘어놓는 필터 칩.
///
/// `PillPicker` 와 역할이 갈린다 — 저쪽은 **둘·셋을 화면 폭에 균등하게 나눠 갖는**
/// 세그먼트고(재정 탭의 전체·입금·출금), 이건 **넷 이상이라 균등 분할이 안 되는**
/// 필터다. 넷을 균등하게 자르면 칩 하나가 "대기중 3" 을 담지 못한다.
///
/// 개수는 칩 안에 같이 적는다. 이 앱이 세그먼트 컨트롤 대신 직접 만든 이유가
/// 개수를 같이 보여주려는 것이다 (DESIGN.md 6번).
struct ChipSelector<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let label: String
        let count: Int

        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.small) {
                ForEach(items) { item in
                    chip(item)
                }
            }
            .padding(.horizontal, DS.Spacing.screen)
        }
    }

    private func chip(_ item: Item) -> some View {
        let isSelected = item.value == selection
        return Button {
            withAnimation(DS.Motion.control) { selection = item.value }
        } label: {
            HStack(spacing: DS.Spacing.tight) {
                Text(item.label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text("\(item.count)")
                    .font(.caption)
                    .opacity(0.7)
            }
            .selectableChip(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
