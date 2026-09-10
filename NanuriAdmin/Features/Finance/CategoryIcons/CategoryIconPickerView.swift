import SwiftUI

/// 한 카테고리에 붙일 아이콘을 고르는 화면. 관리 화면에서 카테고리 줄을 누르면
/// **push 로 열린다**(관리 화면이 풀스크린이라 그 위에 시트를 얹지 못한다 —
/// 불러오기 흐름과 같은 이유, DESIGN.md §13).
///
/// **고르면 바로 저장하고 돌아간다.** 저장 버튼을 따로 두지 않는다 — 한 번 탭이
/// 곧 결정이다. 이미 붙인 게 있으면 맨 위 "아이콘 없음" 으로 뗀다.
struct CategoryIconPickerView: View {
    let category: String
    @ObservedObject var store: CategoryIconStore

    @Environment(\.dismiss) private var dismiss

    private var current: String? { store.iconId(for: category) }

    private let columns = [GridItem(.adaptive(minimum: 60), spacing: DS.Spacing.medium)]

    var body: some View {
        VStack(spacing: 0) {
            AdminHeaderView(
                showsNotifications: false,
                center: { Text(category).headerTitle().lineLimit(1) },
                leading: { HeaderBackButton(label: "뒤로") { dismiss() } },
                trailing: { EmptyView() }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    if current != nil {
                        removeRow
                    }
                    ForEach(CategoryIconCatalog.grouped, id: \.group.id) { section in
                        VStack(alignment: .leading, spacing: DS.Spacing.small) {
                            Text(section.group.rawValue).rowSubtext()
                            LazyVGrid(columns: columns, spacing: DS.Spacing.medium) {
                                ForEach(section.icons) { icon in
                                    iconCell(icon)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.sheetEdge)
            }
        }
        .screenBackground(DS.Surface.page)
    }

    /// 붙여 둔 아이콘을 뗀다.
    private var removeRow: some View {
        Button {
            store.set(nil, for: category)
            dismiss()
        } label: {
            HStack(spacing: DS.Spacing.medium) {
                Image(systemName: "xmark.circle")
                    .font(DS.Icon.font(DS.Icon.feature))
                    .foregroundColor(DS.Palette.danger)
                    .frame(width: DS.Icon.feature)
                Text("아이콘 없음").typeStyle(DS.Typo.body1).foregroundColor(DS.Ink.primary)
                Spacer()
            }
            .padding(DS.Spacing.screen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle(padding: 0)
    }

    private func iconCell(_ icon: CategoryIcon) -> some View {
        let isSelected = current == icon.id
        return Button {
            store.set(icon.id, for: category)
            dismiss()
        } label: {
            VStack(spacing: DS.Spacing.tight) {
                RoundedRectangle(cornerRadius: DS.Radius.l)
                    .fill(isSelected ? DS.Surface.brandWeak : DS.Surface.secondary)
                    .overlay(
                        CategoryIconImage(iconId: icon.id)
                            .frame(width: DS.Icon.feature, height: DS.Icon.feature)
                            .foregroundColor(isSelected ? DS.Ink.brand : DS.Ink.primary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.l)
                            .strokeBorder(DS.Ink.brand,
                                          lineWidth: isSelected ? DS.Line.focusedWidth : 0)
                    )
                    .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
                Text(icon.label)
                    .typeStyle(DS.Typo.captionS)
                    .foregroundColor(isSelected ? DS.Ink.brand : DS.Ink.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
