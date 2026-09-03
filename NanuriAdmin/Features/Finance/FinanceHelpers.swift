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

/// **장부가 하나도 없을 때만** 나오는 화면. 사실상 최초 1회다.
///
/// 예전에는 재정 탭에 들어올 때마다 여기서 장부를 골랐는데, 통장이 하나라
/// 고를 것이 없었다. 지금은 `FinanceViewModel.start()` 가 받는 즉시 열고,
/// 정말 하나도 없을 때만 이 화면이 뜬다.
///
/// 그래서 **목록도 지우기도 없다.** 여기서 할 일은 첫 장부를 만드는 것뿐이다.
struct FinanceLedgerGateView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var showNewLedger = false

    var body: some View {
        VStack(spacing: 0) {
            // `titleAction` 을 안 준다. 주면 이름 옆에 ▾ 가 붙는데, ▾ 는 펼쳐진다는
            // 뜻이라 새로고침을 걸면 화살표가 거짓말을 한다 (DESIGN.md 1번).
            // 다시 받는 건 아래로 당겨서 한다.
            AdminHeaderView(title: "재정")

            EmptyStateView(
                title: "장부가 없어요",
                icon: "books.vertical",
                message: "거래를 담을 장부를 하나 만들어요.\n통장 이름으로 지으면 나중에 알아보기 쉬워요."
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
                        .foregroundColor(DS.Ink.onAccent)
                        .clipShape(Capsule())
                }
            }
            // 빈 화면은 스크롤되지 않아서 `.refreshable` 이 안 붙는다 (DESIGN.md 1번).
            // 다른 기기에서 만든 장부가 있으면 당겨서 받으면 열린다.
            .pullToRefresh { await viewModel.start() }
        }
        .screenBackground()
        .sheet(isPresented: $showNewLedger) {
            NewLedgerView(viewModel: viewModel)
        }
    }
}

/// 새 장부 생성. **이름만 받는다** — 장부 유형(월별/행사)을 고르던 자리가 있었는데
/// 행사 결산을 안 쓰기로 하면서 고를 것이 하나만 남았다.
struct NewLedgerView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var creating = false

    var body: some View {
        NavigationView {
            Form {
                Section("장부 이름") {
                    TextField("예: 나누리 상시, 2024 체육대회", text: $name)
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
                            if let ledger = await viewModel.createLedger(name: name) {
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

/// 같은 날 **장부 줄**을 묶은 덩어리. 재정 탭 목록이 하루씩 끊어 보여준다.
struct DayGroup: Identifiable {
    let day: Date
    var items: [LedgerRow]

    var id: Date { day }
}

/// 지난달과 견준 한 문장. **요약 밴드와 분석 화면이 같은 문장을 쓴다.**
///
/// 밴드에서 한 줄로 흘려 읽던 문장을 눌러 크게 다시 보는 구조라, 두 화면이 문장을
/// 각자 만들면 같은 달을 두고 다른 말을 하게 된다. 크기만 화면이 정하고
/// **문장과 색은 여기 한 곳에서 나온다.**
struct SpendingComparison {
    /// 지난달 총 출금. **견줄 지난달이 아예 없으면 `nil`** 이다.
    let previousWithdrawal: Int?
    let totalWithdrawal: Int
    let totalDeposit: Int

    /// 견줄 지난달이 있는가. 없으면 선이 하나뿐이라 "견주는 그래프" 가 아니게 된다.
    var hasPrevious: Bool { previousWithdrawal != nil }

    /// **더 썼으면 빨강, 덜 썼으면 파랑.** 그래프의 이 달 선도 같은 색을 쓴다 —
    /// 문장과 그림이 같은 것을 말하고 있다는 걸 색이 묶어 준다.
    ///
    /// 이 앱에서 빨강은 되돌릴 수 없는 것의 색이라 아껴 왔는데, 여기서는 예외로
    /// 둔다. 지출이 늘어난 건 되돌릴 수 없는 일이 맞고, 견주는 자리라 색이
    /// 없으면 문장이 그냥 흘러간다.
    var color: Color {
        guard let previousWithdrawal else { return DS.Ink.brand }
        return totalWithdrawal > previousWithdrawal ? DS.Palette.danger : DS.Palette.deposit
    }

    /// 한 문장. 견줄 지난달이 없으면 이 달 수지를 대신 말한다.
    ///
    /// **금액 조각만 굵기와 색을 달리 준다.** 문장 전체를 강조하면 밴드에서
    /// 제일 무거운 덩어리가 되는데, 그 자리는 위의 두 수 것이다. 크기는 붙이지
    /// 않는다 — 밴드는 작게, 분석 화면은 크게 같은 문장을 그린다.
    var text: Text {
        guard let previousWithdrawal else {
            let net = totalDeposit - totalWithdrawal
            return net < 0
                ? Text("\(amountPart(-net)) 더 나갔어요")
                : Text("\(amountPart(net)) 남았어요")
        }
        let diff = totalWithdrawal - previousWithdrawal
        if diff == 0 { return Text("지난달과 똑같이 썼어요") }
        return diff > 0
            ? Text("지난달보다 \(amountPart(diff)) 더 나갔어요")
            : Text("지난달보다 \(amountPart(-diff)) 덜 나갔어요")
    }

    /// 문장 안에 들어가는 금액은 만 단위로 줄인다 — 문장은 정확한 수를 읽는
    /// 자리가 아니라 크기를 가늠하는 자리다. 정확한 수는 요약 밴드 두 칸에 있다.
    private func amountPart(_ amount: Int) -> Text {
        let text = amount >= 10_000
            ? "\((amount / 10_000).formatted())만원"
            : "\(amount.formatted())원"
        return Text(text).fontWeight(.bold).foregroundColor(color)
    }
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
