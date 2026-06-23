import SwiftUI

struct PillPicker: View {
    let tabs: [(label: String, count: Int)]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = index
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tabs[index].label)
                            .font(.subheadline)
                            .fontWeight(selection == index ? .semibold : .regular)
                        Text("\(tabs[index].count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(selection == index ? .secondary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == index ? Color(.systemBackground) : Color.clear)
                            .shadow(color: .black.opacity(selection == index ? 0.07 : 0), radius: 4, x: 0, y: 2)
                    )
                    .foregroundColor(selection == index ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
