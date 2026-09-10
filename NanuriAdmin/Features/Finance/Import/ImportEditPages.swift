import SwiftUI

// MARK: - 편집 페이지 (push)

/// 카테고리 입력. 이미 쓴 이름을 칩으로 먼저 보여준다.
struct ImportCategoryPage: View {
    let suggestions: [String]
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            AdminHeaderView(
                showsNotifications: false,
                center: { Text("카테고리").headerTitle() },
                leading: { HeaderBackButton { dismiss() } },
                trailing: { EmptyView() }
            )
            .background(DS.Surface.card)
            VStack(alignment: .leading, spacing: DS.Spacing.medium) {
                TextField("예: 회비, 식대, 시상품", text: $text)
                    .typeStyle(DS.Typo.body1).foregroundColor(DS.Ink.primary)
                    .padding(DS.Spacing.medium)
                    .background(DS.Surface.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                CategorySuggestionChips(suggestions: suggestions, selected: $text)
                Text("비워 두면 카테고리 없이 들어가요. 나중에 장부에서도 붙일 수 있어요.")
                    .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.tertiary)
            }
            .padding(.horizontal, DS.Spacing.screen)
            Spacer()
        }
        .background(DS.Surface.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 적요(장부에 적힐 이름) 입력.
struct ImportTextPage: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.medium) {
            AdminHeaderView(
                showsNotifications: false,
                center: { Text(title).headerTitle() },
                leading: { HeaderBackButton { dismiss() } },
                trailing: { EmptyView() }
            )
            .background(DS.Surface.card)

            VStack(alignment: .leading, spacing: DS.Spacing.small) {
                TextField(placeholder, text: $text)
                    .typeStyle(DS.Typo.body1).foregroundColor(DS.Ink.primary)
                    .padding(DS.Spacing.medium)
                    .background(DS.Surface.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
                Text("장부에 적힐 이름이에요. 비워 두면 은행 적요가 그대로 들어가요.")
                    .typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.tertiary)
            }
            .padding(.horizontal, DS.Spacing.screen)
            Spacer()
        }
        .background(DS.Surface.page.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
