import SwiftUI

/// **카테고리 아이콘 관리 — 분석하고, 고른다.**
///
/// 재정 탭 메뉴(≡)의 "카테고리 아이콘" 이 여는 풀스크린이다. 두 가지를 한다.
/// ① 장부에 쓴 카테고리를 **많이 쓴 것부터** 건수와 함께 보여준다(분석).
/// ② 한 줄을 누르면 아이콘 피커로 push, 고른 그림이 그 줄에 바로 뜬다.
///
/// 아이콘을 붙이면 재정 탭 목록에서 그 카테고리 항목들이 왼쪽에 그 그림을
/// 썸네일처럼 달게 된다(`LedgerRowView`). 매칭 결과 화면(`StatementImportView`)의
/// 행 문법을 재정 목록에 들여온 것이다.
///
/// 타이틀·뒤로가 있어 시트가 아니라 풀스크린이고(DESIGN.md §1), 피커를 push 로
/// 받으려 `NavigationStack` 을 두른다(§13 의 불러오기 흐름과 같은 문법).
struct CategoryIconManagerView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @ObservedObject var store: CategoryIconStore

    @Environment(\.dismiss) private var dismiss
    /// push 로 연 카테고리. `nil` 이면 목록.
    @State private var picking: String?

    private var usage: [(name: String, count: Int)] { viewModel.categoryUsage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AdminHeaderView(
                    showsNotifications: false,
                    center: { Text("카테고리 아이콘").headerTitle() },
                    leading: { HeaderBackButton(label: "닫기") { dismiss() } },
                    trailing: { EmptyView() }
                )
                content
            }
            .screenBackground(DS.Surface.page)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $picking) { category in
                CategoryIconPickerView(category: category, store: store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if usage.isEmpty {
            EmptyStateView(
                title: "붙일 카테고리가 아직 없어요",
                icon: "tag",
                message: "목록에서 항목에 카테고리를 붙이면\n여기서 그 카테고리에 아이콘을 정할 수 있어요"
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.small) {
                    Text(headerNote)
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.tertiary)
                        .padding(.horizontal, DS.Spacing.s4)
                        .padding(.bottom, DS.Spacing.tight)

                    VStack(spacing: 0) {
                        ForEach(Array(usage.enumerated()), id: \.element.name) { offset, entry in
                            categoryRow(entry.name, count: entry.count, first: offset == 0)
                        }
                    }
                    .cardStyle(padding: 0)
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.medium)
                .padding(.bottom, DS.Spacing.sheetEdge)
            }
        }
    }

    private var headerNote: String {
        let assigned = usage.filter { store.iconId(for: $0.name) != nil }.count
        return assigned == 0
            ? "자주 쓴 카테고리 \(usage.count)개예요. 눌러서 아이콘을 정해요."
            : "\(usage.count)개 중 \(assigned)개에 아이콘을 붙였어요."
    }

    private func categoryRow(_ name: String, count: Int, first: Bool) -> some View {
        Button {
            picking = name
        } label: {
            HStack(spacing: DS.Spacing.medium) {
                tile(for: name)
                Text(name).rowTitle().lineLimit(1)
                Spacer(minLength: DS.Spacing.small)
                Text("\(count)건")
                    .typeStyle(DS.Typo.body3)
                    .foregroundColor(DS.Ink.placeholder)
                Image(systemName: "chevron.right")
                    .font(DS.Icon.font(DS.Icon.m))
                    .foregroundColor(DS.Ink.placeholder)
            }
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.medium)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if !first {
                    Rectangle().fill(DS.Line.default).frame(height: DS.Line.hairline)
                        .padding(.leading, DS.Spacing.screen + DS.Size.rowAvatar + DS.Spacing.medium)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 왼쪽 아이콘 타일. 정해 뒀으면 그 그림을, 아니면 옅은 자리표시를.
    @ViewBuilder
    private func tile(for name: String) -> some View {
        if let id = store.iconId(for: name) {
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .fill(DS.Surface.secondary)
                .overlay(
                    CategoryIconImage(iconId: id)
                        .frame(width: DS.Icon.feature, height: DS.Icon.feature)
                        .foregroundColor(DS.Ink.primary)
                )
                .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
        } else {
            RoundedRectangle(cornerRadius: DS.Radius.m)
                .strokeBorder(style: StrokeStyle(lineWidth: DS.Line.focusedWidth, dash: [4]))
                .foregroundColor(DS.Ink.placeholder)
                .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
                .overlay(
                    Image(systemName: "plus")
                        .font(DS.Icon.font(DS.Icon.m))
                        .foregroundColor(DS.Ink.placeholder)
                )
        }
    }
}
