import SwiftUI

/// 칩들이 줄 끝에서 자동으로 다음 줄로 넘어가는 간단한 흐름 레이아웃.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = DS.Spacing.tight

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
                HStack(spacing: DS.Spacing.small) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            selected = suggestion
                        } label: {
                            // 글자 크기는 칩이 정한다 — Label 스케일이 컨트롤 전용이다.
                            Text(suggestion)
                                .selectableChip(isSelected: selected == suggestion)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, DS.Spacing.tight)
            }
            .listRowInsets(EdgeInsets(top: DS.Spacing.tight, leading: DS.Spacing.s4,
                                      bottom: DS.Spacing.tight, trailing: DS.Spacing.s4))
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
                            // 이 화면에서 할 일이 이것뿐이라 주요 동작이다.
                            Label("새 장부 만들기", systemImage: "plus")
                                .typeStyle(DS.Typo.labelM)
                                .padding(.horizontal, DS.Spacing.section)
                                .frame(height: DS.Size.buttonM)
                                .background(DS.Palette.accent)
                                .foregroundColor(DS.Ink.inverse)
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

    /// 원문 list-row 를 그대로 따른다 — 44pt 아바타 + 제목/부제 스택 + 우측 화살표.
    private func row(_ ledger: Ledger) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            Image(systemName: ledger.mode.icon)
                .font(DS.Icon.font(DS.Icon.l))
                .foregroundColor(DS.Ink.brand)
                .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
                .background(DS.Surface.brandWeak)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(ledger.name)
                    .rowTitle()
                Text(ledger.mode.title)
                    .rowSubtext()
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(DS.Icon.font(DS.Icon.m))
                .foregroundColor(DS.Ink.placeholder)
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
                        .typeStyle(DS.Typo.body3)
                        .foregroundColor(DS.Ink.secondary)
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

/// 같은 날 거래를 묶은 덩어리. 재정 탭 목록이 카드 한 장에 하루를 담는다.
struct DayGroup: Identifiable {
    let day: Date
    var items: [BankTransaction]

    var id: Date { day }
}

extension Int {
    /// 좁은 자리에 넣는 줄인 금액. 부호는 붙이지 않으므로 **절댓값을 넘긴다.**
    ///
    /// ```
    ///      8,500 → "8,500"
    ///     87,180 → "8.7만"
    ///    892,500 → "89.3만"
    ///  1,685,080 → "168.5만"
    /// 12,340,000 → "1,234만"
    /// ```
    ///
    /// 규칙 셋:
    /// - **만 미만은 그대로** 쓴다. `0.85만` 은 줄인 게 아니라 읽기만 어려워진다.
    /// - 소수는 **첫째 자리까지만**. 좁은 칸에서 자릿수가 늘면 결국 다시 줄어든다.
    /// - **`.0` 은 뗀다.** `50.0만` 이 `50만` 보다 정확해 보이지만 주는 정보는 같다.
    ///
    /// 천만을 넘기면 소수를 버린다 — 그쯤 되면 소수 한 자리가 가리키는 천 원
    /// 단위가 수 전체에서 뜻이 없다.
    var compactAmount: String {
        if self >= 100_000_000 {
            let value = Double(self) / 100_000_000
            return "\(trimmed(value))억"
        }
        if self >= 10_000_000 {
            return "\((self / 10_000).formatted())만"
        }
        if self >= 10_000 {
            let value = Double(self) / 10_000
            return "\(trimmed(value))만"
        }
        return formatted()
    }

    private func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded))"
            : String(format: "%.1f", rounded)
    }
}
