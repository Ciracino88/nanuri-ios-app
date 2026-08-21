import SwiftUI

/// 칩들이 줄 끝에서 자동으로 다음 줄로 넘어가는 간단한 흐름 레이아웃.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 카테고리 입력 시 기존 카테고리를 가로 스크롤 칩으로 추천 (탭하면 채워짐).
/// 거래 편집·분할 편집 등에서 공용으로 사용.
struct CategorySuggestionChips: View {
    let suggestions: [String]
    @Binding var selected: String

    var body: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            selected = suggestion
                        } label: {
                            Text(suggestion)
                                .font(.caption)
                                .selectableChip(isSelected: selected == suggestion)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }
}

/// 재정 탭 진입 시 어느 장부(통장)를 열지 고르는 게이트 화면.
struct FinanceLedgerGateView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showNewLedger = false

    var body: some View {
        VStack(spacing: 0) {
            AdminHeaderView(title: "재정") {
                Task { await viewModel.fetchLedgers() }
            } trailing: {
                HeaderIconButton(systemName: "plus", label: "새 장부") {
                    showNewLedger = true
                }
            }

            Group {
                if viewModel.ledgers.isEmpty {
                    EmptyStateView(
                        title: "장부가 없어요",
                        icon: "books.vertical",
                        message: "통장별로 장부를 만들어 관리해요.\n상시 계좌는 '월별 회계', 행사 통장은 '행사 결산'."
                    ) {
                        Button {
                            showNewLedger = true
                        } label: {
                            Label("새 장부 만들기", systemImage: "plus")
                                .fontWeight(.semibold)
                                .padding(.horizontal, DS.Spacing.screen)
                                .padding(.vertical, 10)
                                .background(DS.Palette.deposit)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    List {
                        ForEach(viewModel.ledgers) { ledger in
                            Button {
                                Task { await viewModel.selectLedger(ledger) }
                            } label: {
                                row(ledger)
                            }
                            .buttonStyle(.plain)
                            .cardRow()
                        }
                        .onDelete { indexSet in
                            indexSet.map { viewModel.ledgers[$0] }.forEach { ledger in
                                Task { await viewModel.deleteLedger(ledger) }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .screenBackground()
                }
            }
        }
        .screenBackground()
        .sheet(isPresented: $showNewLedger) {
            NewLedgerView(viewModel: viewModel)
        }
        .task { await viewModel.fetchLedgers() }
    }

    /// 행이 크고 개수가 적은 목록이라 제목만 `.headline` 이다 (DESIGN.md 3).
    private func row(_ ledger: Ledger) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            Image(systemName: ledger.mode.icon)
                .font(.system(size: DS.Icon.feature))
                .foregroundColor(DS.Palette.deposit)
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .background(DS.Palette.deposit.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(ledger.name)
                    .font(.headline)
                    // .headline 이 물고 오는 굵기가 곧 우리 semibold 다. 명시해 둔다.
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(ledger.mode.title)
                    .rowSubtext()
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .cardStyle()
    }
}

/// 새 장부 생성 (이름 + 유형).
struct NewLedgerView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var mode: FinanceReportMode = .monthly
    @State private var creating = false

    var body: some View {
        NavigationView {
            Form {
                Section("장부 이름") {
                    TextField("예: 나누리 상시, 2024 체육대회", text: $name)
                }
                Section("유형") {
                    Picker("유형", selection: $mode) {
                        Text("월별 회계").tag(FinanceReportMode.monthly)
                        Text("행사 결산").tag(FinanceReportMode.event)
                    }
                    .pickerStyle(.segmented)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("새 장부")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("만들기") {
                        Task {
                            creating = true
                            if let ledger = await viewModel.createLedger(name: name, mode: mode) {
                                dismiss()
                                await viewModel.selectLedger(ledger)
                            }
                            creating = false
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                }
            }
        }
    }
}

/// 내보낼 파일을 sheet(item:)에 넘기기 위한 래퍼.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// 미리볼 보고서를 sheet(item:)에 넘기기 위한 래퍼.
struct ReportPreview: Identifiable {
    let id = UUID()
    let html: String
    let title: String
}

/// UIActivityViewController(공유시트) 래퍼. 파일 앱 저장·메일·메신저 공유 등을 지원.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
