import SwiftUI

struct PillPicker: View {
    let tabs: [(label: String, count: Int)]
    @Binding var selection: Int
    @Namespace private var pillNamespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    withAnimation(DS.Motion.control) {
                        selection = index
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tabs[index].label)
                            .font(.subheadline)
                            .fontWeight(selection == index ? .semibold : .regular)
                        Text("\(tabs[index].count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selection == index {
                            RoundedRectangle(cornerRadius: DS.Radius.button)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
                                .matchedGeometryEffect(id: "pill", in: pillNamespace)
                        }
                    }
                    .foregroundColor(selection == index ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DS.Spacing.tight)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}
